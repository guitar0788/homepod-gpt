"""Confirmed profile metadata and optional, strictly gated semantic retrieval."""
import hashlib
import json
import math
import os
import re
import time

import httpx

MODEL = "gemini-embedding-001"
DIM = 768
CATEGORIES = {"preference", "goal", "routine", "project", "communication", "background", "other"}
BLOCK = re.compile(r"密码|口令|令牌|密钥|账号|证件|身份证|住址|地址|手机号|电话|银行卡|病|药|过敏|收入|工资|性取向|宗教|政治|私密|邮箱|@|https?://|sk-|[0-9]{5,}", re.I)

def metadata(data):
    if not isinstance(data, dict):
        return ("other", "")
    category, subject = data.get("category"), data.get("subject")
    if category not in CATEGORIES:
        category = "other"
    subject = subject.strip().lower() if isinstance(subject, str) else ""
    if not re.fullmatch(r"[\w\u4e00-\u9fff -]{1,40}", subject) or BLOCK.search(subject):
        subject = ""
    return category, subject

def store(db, memory_id, category, subject):
    db.execute("INSERT INTO memory_profile(memory_id,category,subject) VALUES (?,?,?) ON CONFLICT(memory_id) DO UPDATE SET category=excluded.category,subject=excluded.subject",
               (memory_id, category, subject))

def conflicts(db, subject, fact):
    if not subject:
        return []
    return [row[0] for row in db.execute(
        "SELECT m.fact FROM memory m JOIN memory_profile p ON p.memory_id=m.id WHERE p.subject=? AND m.fact<>? ORDER BY m.id DESC LIMIT 3",
        (subject, fact))]

def entries(db):
    rows = list(db.execute("SELECT m.id,m.fact,p.category,p.subject FROM memory m JOIN memory_profile p ON p.memory_id=m.id ORDER BY m.id DESC LIMIT 100"))
    counts = {}
    for _, _, _, subject in rows:
        if subject:
            counts[subject] = counts.get(subject, 0) + 1
    return [{"id": i, "fact": fact, "category": category, "subject": subject,
             "review": bool(subject and counts[subject] > 1)} for i,fact,category,subject in rows]

def invalidate(db, memory_id):
    db.execute("DELETE FROM memory_profile WHERE memory_id=?", (memory_id,))
    db.execute("DELETE FROM memory_vectors WHERE memory_id=?", (memory_id,))

def enabled():
    return (os.getenv("GEMINI_EMBEDDINGS_ENABLED") == "1" and
            os.getenv("GEMINI_EMBEDDINGS_VERIFIED_FREE") == "1" and
            os.getenv("GEMINI_EMBEDDINGS_PRIVACY_ACCEPTED") == "1" and
            bool(os.getenv("GEMINI_KEY")))

def digest(fact):
    return hashlib.sha256(fact.encode("utf-8")).hexdigest()

def normalized(values):
    if not isinstance(values, list) or len(values) != DIM:
        raise ValueError("invalid vector")
    if any(type(v) not in (int, float) or not math.isfinite(v) for v in values):
        raise ValueError("invalid vector values")
    norm = math.sqrt(sum(v*v for v in values))
    if not norm or not math.isfinite(norm):
        raise ValueError("invalid vector norm")
    return [v/norm for v in values]

def embed(query, documents):
    if not enabled():
        raise ValueError("embedding disabled")
    requests = []
    for text, task in [(query, "RETRIEVAL_QUERY")] + [(d, "RETRIEVAL_DOCUMENT") for d in documents]:
        requests.append({"model": "models/"+MODEL, "content": {"parts": [{"text":text}]},
                         "taskType":task,"outputDimensionality":DIM})
    response = httpx.post("https://generativelanguage.googleapis.com/v1beta/models/"+MODEL+":batchEmbedContents",
                          headers={"x-goog-api-key":os.environ["GEMINI_KEY"]},
                          json={"requests":requests}, timeout=httpx.Timeout(4.0,connect=2.0))
    response.raise_for_status()
    rows = response.json()["embeddings"]
    if len(rows) != len(requests):
        raise ValueError("wrong embedding count")
    return [normalized(row["values"]) for row in rows]

def retrieve(db_factory, reserve, question, candidates, fallback):
    # Candidate tuples are id and confirmed fact. No history or context is embedded.
    if not enabled() or BLOCK.search(question) or not candidates:
        return fallback
    safe = [(i, fact) for i,fact in candidates if not BLOCK.search(fact)]
    if not safe:
        return fallback
    with db_factory() as db:
        cached = {i:(fingerprint, vector) for i,fingerprint,vector in db.execute(
            "SELECT memory_id,fingerprint,vector FROM memory_vectors WHERE model=?", (MODEL,))}
        ready = {}
        missing = []
        for i,fact in safe:
            item = cached.get(i)
            try:
                if item and item[0] == digest(fact):
                    ready[i] = normalized(json.loads(item[1]))
                    continue
            except (ValueError, TypeError, OverflowError):
                pass
            missing.append((i,fact))
        batch = missing[:4]
        # Independent lifetime-day budget, reserve before any network operation.
        bucket = "embedding-day:" + time.strftime("%Y-%m-%d",time.gmtime())
        db.execute("DELETE FROM limits WHERE bucket LIKE 'embedding-day:%' AND bucket < ?", (bucket,))
        if not reserve(db,bucket,10):
            return fallback
    try:
        vectors = embed(question[:500],[fact for _,fact in batch])
    except (httpx.HTTPError, ValueError, TypeError, KeyError, IndexError, OverflowError):
        return fallback
    query = vectors[0]
    with db_factory() as db:
        for (i,fact), vector in zip(batch,vectors[1:]):
            # A concurrent edit/delete must not leave a stale vector.
            current = db.execute("SELECT fact FROM memory WHERE id=?", (i,)).fetchone()
            if not current or current[0] != fact:
                continue
            db.execute("INSERT INTO memory_vectors(memory_id,model,fingerprint,vector) VALUES (?,?,?,?) ON CONFLICT(memory_id) DO UPDATE SET model=excluded.model,fingerprint=excluded.fingerprint,vector=excluded.vector",
                       (i,MODEL,digest(fact),json.dumps(vector,separators=(",",":"))))
            ready[i] = vector
    ranked = sorted(((sum(x*y for x,y in zip(query,ready[i])),fact) for i,fact in safe if i in ready),
                    reverse=True)
    output = [fact[:350] for score,fact in ranked[:6] if score >= 0.45]
    return list(dict.fromkeys(output + fallback))[:12]
