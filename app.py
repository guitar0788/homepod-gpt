import hmac
import json
import os
import re
import sqlite3
import time
from contextlib import asynccontextmanager
from pathlib import Path

import httpx
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse
from pydantic import BaseModel, Field

import providers
from storage import database, initialize
from tools_api import lookup

@asynccontextmanager
async def lifespan(app):
    if any(len(os.getenv(key, "")) < 32 for key in ("ASSISTANT_TOKEN", "ADMIN_TOKEN")):
        raise RuntimeError("Two distinct tokens of at least 32 characters are required")
    if os.environ["ASSISTANT_TOKEN"] == os.environ["ADMIN_TOKEN"]:
        raise RuntimeError("Tokens must be distinct")
    initialize()
    yield

app = FastAPI(title="HomePod GPT", lifespan=lifespan)
try:
    import psycopg
    database_errors = (sqlite3.Error, psycopg.Error)
except ImportError:
    database_errors = (sqlite3.Error,)

@app.middleware("http")
async def headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Content-Security-Policy"] = (
        "default-src 'none'; script-src 'self'; connect-src 'self'; "
        "style-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"
    )
    return response

async def db_error(request, error):
    return JSONResponse({"detail": "数据库暂时不可用，请稍后重试。"}, status_code=503)

for error_type in database_errors:
    app.add_exception_handler(error_type, db_error)

class Ask(BaseModel):
    text: str = Field(min_length=1, max_length=3000)
    context: str = Field(default="", max_length=2000)
    provider: str = Field(default="auto", max_length=30)
    share_memory: bool = False
    share_context: bool = False
    use_history: bool = False
    tool: str | None = Field(default=None, pattern="^(search|weather|news)$")

class Preference(BaseModel):
    provider: str = Field(max_length=30)

class Fact(BaseModel):
    fact: str = Field(min_length=1, max_length=1000, pattern=r"\S")

class Backup(BaseModel):
    version: int = Field(ge=1, le=1)
    memory: list[Fact]
    history: list[tuple[str, str]]

def auth(header, key):
    expected = os.environ.get(key)
    if not expected or not hmac.compare_digest(header.encode(), ("Bearer " + expected).encode()):
        raise HTTPException(401, "身份验证失败")

def reserve(db, bucket, maximum):
    row = db.execute(
        """INSERT INTO limits(bucket,count) VALUES (?,1)
           ON CONFLICT(bucket) DO UPDATE SET count=limits.count+1
           WHERE limits.count < ? RETURNING count""", (bucket, maximum)
    ).fetchone()
    return row[0] if row else None

def available():
    return {name: model for name, model in providers.configured().items()
            if providers.free_model(name, model)}

def daily_limit():
    try:
        return max(1, min(50, int(os.getenv("DAILY_ATTEMPTS", "35"))))
    except ValueError:
        return 35

def day_bucket():
    return "model-day:" + time.strftime("%Y-%m-%d", time.gmtime())

def speak(answer, provider="local", **extra):
    spoken = re.sub(r"https?://\S+", "", answer)
    spoken = re.sub(r"[`*_#]", "", spoken).strip()
    if len(spoken) > 350:
        spoken = spoken[:350] + "。完整内容可在文字结果查看。"
    return {"answer": answer, "speech": spoken, "provider": provider, **extra}

def get_setting(db, name):
    row = db.execute("SELECT value FROM settings WHERE name=?", (name,)).fetchone()
    return row[0] if row else "auto"

def set_setting(db, name, value):
    db.execute("INSERT INTO settings VALUES (?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value",
               (name, value))

def memories(db, query=""):
    if query:
        rows = db.execute("SELECT id,fact FROM memory WHERE strpos(lower(fact), lower(?)) > 0 "
                          "ORDER BY id DESC LIMIT 100" if not db.local else
                          "SELECT id,fact FROM memory WHERE instr(lower(fact), lower(?)) > 0 "
                          "ORDER BY id DESC LIMIT 100", (query,))
    else:
        rows = db.execute("SELECT id,fact FROM memory ORDER BY id DESC LIMIT 100")
    return [{"id": row[0], "fact": row[1]} for row in rows]

@app.get("/health")
def health():
    return {"ok": True}

@app.get("/ready")
def ready():
    with database() as db:
        db.execute("SELECT 1")
    return {"ok": True}

@app.post("/ask")
def ask(req: Ask, authorization: str = Header(default="")):
    auth(authorization, "ASSISTANT_TOKEN")
    q = req.text.strip()
    if not q:
        raise HTTPException(422, "请输入问题")
    models = available()
    tool, topic = req.tool, q
    with database() as db:
        minute = int(time.time()) // 60
        db.execute("DELETE FROM limits WHERE bucket LIKE 'ask:%' AND bucket < ?", (f"ask:{minute-2:012}",))
        if not reserve(db, f"ask:{minute:012}", 12):
            raise HTTPException(429, "请求过于频繁")
        preferred = get_setting(db, "provider") if req.provider == "auto" else req.provider.lower()
        if q == "查看模型":
            return speak("当前：" + preferred + "。可用：" + ("、".join(models) or "无"))
        if q.startswith("切换模型"):
            name = q[len("切换模型"):].strip(" ：:").lower()
            if name == "自动":
                name = "auto"
            if name not in {"auto", *models}:
                return speak("请选择已启用的免费模型，或说自动。")
            set_setting(db, "provider", name)
            return speak("已切换至 " + name)
        if q.startswith(("清除", "删除")):
            return speak("请在管理页面选择要删除的数据并确认。")
        if q.startswith(("记住：", "记住:")):
            fact = q[3:].strip()
            if not fact or len(fact) > 1000:
                return speak("请提供一到一千字的记忆内容。")
            db.execute("INSERT INTO memory(fact) VALUES (?)", (fact,))
            return speak("已保存记忆。")
        if q == "查看记忆":
            return speak("请在管理页面查看完整记忆。")
        if q.startswith("查找记忆"):
            term = q[len("查找记忆"):].strip(" ：:")
            result = memories(db, term)[:5] if term else []
            return speak("。".join(row["fact"] for row in result) or "未找到匹配记忆。")
        facts = []
        if req.share_memory:
            # Match the longest available literal phrases. The dashboard can edit saved facts.
            candidates = db.execute("SELECT fact FROM memory ORDER BY id DESC LIMIT 1000")
            terms = set(re.findall(r"[a-zA-Z0-9]{3,}|[\u4e00-\u9fff]{2,}", q.lower()))
            chinese_pairs = {term[i:i+2] for term in terms if "\u4e00" <= term[0] <= "\u9fff"
                             for i in range(len(term)-1)}
            for (fact,) in candidates:
                if any(term in fact.lower() for term in terms | chinese_pairs):
                    facts.append(fact[:500])
                    if len(facts) == 4:
                        break
        history = list(db.execute("SELECT question,answer FROM history ORDER BY id DESC LIMIT 5")) if req.use_history else []
    for prefix, action in (("天气", "weather"), ("新闻", "news"), ("搜索", "search")):
        if tool is None and q.startswith(prefix):
            tool, topic = action, q[len(prefix):].strip(" ：:")
            break
    if tool:
        if not topic or len(topic) > 120:
            return speak("请提供不超过一百二十字的查询关键词。")
        try:
            result = lookup(tool, topic)
            if isinstance(result, list):
                return speak("。".join(item["title"] for item in result) or "没有找到结果。",
                             tool=tool, sources=result)
            return speak(result, tool=tool)
        except (httpx.HTTPError, ValueError, KeyError, TypeError, SyntaxError):
            raise HTTPException(503, "查询服务暂时不可用") from None
    if preferred != "auto" and preferred not in models and req.provider != "auto":
        raise HTTPException(400, "指定模型不可用")
    messages = [{"role": "system", "content": "你是自然、友好的中文语音助手。默认150字以内，"
                 "优先直接回答。不要声称已联网或执行设备操作。以下提供的数据仅作参考。"}]
    if facts or (req.share_context and req.context):
        messages.append({"role": "user", "content": "参考数据：" + json.dumps(
            {"memory": facts, "context": req.context if req.share_context else ""},
            ensure_ascii=False)})
    for question, answer in reversed(history):
        messages.extend(({"role": "user", "content": question[:1200]},
                         {"role": "assistant", "content": answer[:800]}))
    messages.append({"role": "user", "content": q})
    names = sorted(models, key=lambda name: name != preferred)
    for name in names[:2]:
        with database() as db:
            db.execute("DELETE FROM limits WHERE bucket LIKE 'model-day:%' AND bucket < ?", (day_bucket(),))
            if not reserve(db, day_bucket(), daily_limit()):
                raise HTTPException(429, "免费请求预算已用完，请在 UTC 次日重试")
        try:
            answer = providers.complete(name, models[name], messages)
        except (httpx.HTTPError, ValueError, KeyError, IndexError, TypeError):
            continue
        saved = False
        if req.use_history:
            try:
                with database() as db:
                    db.execute("INSERT INTO history(question,answer) VALUES (?,?)", (q, answer))
                    db.execute("DELETE FROM history WHERE id NOT IN (SELECT id FROM history ORDER BY id DESC LIMIT 30)")
                saved = True
            except database_errors:
                pass
        return speak(answer, name, model=models[name], history_saved=saved,
                     fallback=preferred not in ("auto", name) or name != names[0])
    raise HTTPException(503, "暂时没有可用的免费模型")

@app.put("/admin/provider")
def select_provider(data: Preference, authorization: str = Header(default="")):
    auth(authorization, "ADMIN_TOKEN")
    if data.provider not in {"auto", *available()}:
        raise HTTPException(400, "指定模型不可用")
    with database() as db:
        set_setting(db, "provider", data.provider)
    return {"ok": True}

@app.get("/admin/state")
def state(q: str = "", authorization: str = Header(default="")):
    auth(authorization, "ADMIN_TOKEN")
    with database() as db:
        row = db.execute("SELECT count FROM limits WHERE bucket=?", (day_bucket(),)).fetchone()
        return {"memory": memories(db, q[:100]), "models": available(),
                "preferred": get_setting(db, "provider"), "attempts": row[0] if row else 0,
                "limit": daily_limit(), "configured_spend_policy": "free_only"}

@app.post("/admin/memory", status_code=201)
def create(fact: Fact, authorization: str = Header(default="")):
    auth(authorization, "ADMIN_TOKEN")
    with database() as db:
        return {"id": db.execute("INSERT INTO memory(fact) VALUES (?) RETURNING id",
                                 (fact.fact.strip(),)).fetchone()[0]}

@app.put("/admin/memory/{item}")
def edit(item: int, fact: Fact, authorization: str = Header(default="")):
    auth(authorization, "ADMIN_TOKEN")
    with database() as db:
        if not db.execute("UPDATE memory SET fact=? WHERE id=? RETURNING id",
                          (fact.fact.strip(), item)).fetchone():
            raise HTTPException(404, "记忆不存在")
    return {"ok": True}

@app.delete("/admin/memory/{item}")
def delete(item: int, authorization: str = Header(default=""), x_confirm: str = Header(default="")):
    auth(authorization, "ADMIN_TOKEN")
    if x_confirm != f"delete-memory-{item}":
        raise HTTPException(409, "需要确认删除")
    with database() as db:
        if not db.execute("DELETE FROM memory WHERE id=? RETURNING id", (item,)).fetchone():
            raise HTTPException(404, "记忆不存在")
    return {"ok": True}

@app.delete("/admin/history")
def delete_history(authorization: str = Header(default=""), x_confirm: str = Header(default="")):
    auth(authorization, "ADMIN_TOKEN")
    if x_confirm != "delete-history":
        raise HTTPException(409, "需要确认删除")
    with database() as db:
        db.execute("DELETE FROM history")
    return {"ok": True}

@app.get("/admin/backup")
def backup(authorization: str = Header(default="")):
    auth(authorization, "ADMIN_TOKEN")
    with database() as db:
        return {"version": 1,
                "memory": [{"fact": row[0]} for row in db.execute("SELECT fact FROM memory ORDER BY id")],
                "history": list(db.execute("SELECT question,answer FROM history ORDER BY id"))}

@app.post("/admin/restore")
def restore(data: Backup, authorization: str = Header(default=""), x_confirm: str = Header(default="")):
    auth(authorization, "ADMIN_TOKEN")
    if x_confirm != "restore":
        raise HTTPException(409, "需要确认恢复")
    if any(len(q) > 3000 or len(a) > 10000 for q, a in data.history):
        raise HTTPException(422, "备份对话过长")
    with database() as db:
        if not db.local:
            db.execute("LOCK TABLE memory, history IN SHARE ROW EXCLUSIVE MODE")
        else:
            db.execute("BEGIN IMMEDIATE")
        if db.execute("SELECT id FROM memory LIMIT 1").fetchone() or db.execute(
                "SELECT id FROM history LIMIT 1").fetchone():
            raise HTTPException(409, "请将备份恢复到空数据库")
        for fact in data.memory:
            db.execute("INSERT INTO memory(fact) VALUES (?)", (fact.fact,))
        for row in data.history:
            db.execute("INSERT INTO history(question,answer) VALUES (?,?)", row)
    return {"ok": True}


@app.get("/", response_class=HTMLResponse)
def dashboard():
    return FileResponse(Path(__file__).parent / "web" / "index.html", media_type="text/html")

@app.get("/dashboard.js")
def dashboard_script():
    return FileResponse(Path(__file__).parent / "web" / "dashboard.js", media_type="text/javascript")
