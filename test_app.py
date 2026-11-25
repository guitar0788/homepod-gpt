import os
import tempfile
import unittest
from unittest.mock import patch

import httpx
from fastapi.testclient import TestClient

from app import app
import providers

class AssistantTests(unittest.TestCase):
    def setUp(self):
        directory = self.enterContext(tempfile.TemporaryDirectory())
        self.enterContext(patch.dict(os.environ, {
            "LOCAL_SQLITE": "1", "SQLITE_PATH": directory + "/test.db",
            "ASSISTANT_TOKEN": "a" * 32, "ADMIN_TOKEN": "b" * 32,
            "DAILY_ATTEMPTS": "35", "GROQ_ENABLED": "1", "GROQ_KEY": "mock",
            "GROQ_MODEL": "groq-mock", "GROQ_VERIFIED_FREE_MODELS": "groq-mock",
            "OPENROUTER_ENABLED": "1", "OPENROUTER_KEY": "mock",
            "OPENROUTER_MODEL": "openrouter/free", "OPENAI_ENABLED": "1",
            "OPENAI_KEY": "mock", "OPENAI_MODEL": "paid-mock"
        }, clear=True))
        self.client = self.enterContext(TestClient(app))
        self.voice = {"Authorization": "Bearer " + "a" * 32}
        self.admin = {"Authorization": "Bearer " + "b" * 32}

    def ask(self, text, **extra):
        return self.client.post("/ask", headers=self.voice, json={"text": text, **extra})

    def test_auth_roles(self):
        self.assertEqual(self.client.post("/ask", json={"text": "你好"}).status_code, 401)
        self.assertEqual(self.client.get("/admin/state", headers=self.voice).status_code, 401)
        self.assertEqual(self.client.get("/admin/state", headers=self.admin).status_code, 200)
        self.assertEqual(self.ask("  ").status_code, 422)

    def test_fallback_and_voice_switch(self):
        self.assertIn("groq", self.ask("切换模型：Groq").json()["answer"])
        with patch("providers.complete", side_effect=[httpx.ReadTimeout("mock"), "完成"]) as call:
            result = self.ask("你好").json()
            self.assertEqual(result["provider"], "openrouter")
            self.assertTrue(result["fallback"])
            self.assertEqual([args.args[0] for args in call.call_args_list], ["groq", "openrouter"])
        self.assertEqual(self.ask("切换模型 自动").status_code, 200)
        self.assertEqual(self.client.get("/admin/state", headers=self.admin).json()["preferred"], "auto")
        self.assertNotIn("openai", self.client.get("/admin/state", headers=self.admin).json()["models"])

    def test_budget_counts_failures_and_stops_paid_calls(self):
        with patch.dict(os.environ, {"DAILY_ATTEMPTS": "1"}), patch(
            "providers.complete", side_effect=httpx.ReadTimeout("mock")
        ) as call:
            self.assertEqual(self.ask("你好").status_code, 429)
            self.assertEqual(self.ask("你好").status_code, 429)
            self.assertEqual(call.call_count, 1)

    def test_memory_restart_edit_export_restore_and_confirm(self):
        self.assertEqual(self.ask("记住：我喜欢荔枝").status_code, 200)
        with TestClient(app) as restarted:
            state = restarted.get("/admin/state?q=荔枝", headers=self.admin).json()
            item = state["memory"][0]["id"]
            path = f"/admin/memory/{item}"
            self.assertEqual(restarted.put(path, headers=self.admin,
                                           json={"fact": "我喜欢龙眼"}).status_code, 200)
            saved = restarted.get("/admin/backup", headers=self.admin).json()
            self.assertEqual(saved["memory"], [{"fact": "我喜欢龙眼"}])
            restore = {**self.admin, "X-Confirm": "restore"}
            self.assertEqual(restarted.post("/admin/restore", headers=restore, json=saved).status_code, 409)
            self.assertEqual(restarted.delete(path, headers=self.admin).status_code, 409)
            self.assertEqual(restarted.delete(path, headers={**self.admin, "X-Confirm":
                                                           f"delete-memory-{item}"}).status_code, 200)
            self.assertEqual(restarted.post("/admin/restore", headers=restore, json=saved).status_code, 200)

    def test_context_consent_and_history(self):
        self.ask("记住：荔枝来自广东")
        with patch("providers.complete", return_value="测试回复") as call:
            self.ask("荔枝是什么", context="本地日程")
            self.assertNotIn("广东", str(call.call_args))
            self.assertNotIn("本地日程", str(call.call_args))
            self.ask("荔枝是什么", context="本地日程", share_context=True, share_memory=True, use_history=True)
            self.assertIn("广东", str(call.call_args))
            self.assertIn("本地日程", str(call.call_args))
            self.ask("继续", use_history=True)
            self.assertIn("测试回复", str(call.call_args))

    def test_rate_limit(self):
        for _ in range(12):
            self.assertEqual(self.ask("查看模型").status_code, 200)
        self.assertEqual(self.ask("查看模型").status_code, 429)

    def test_tool_path_does_not_call_model(self):
        with patch("app.lookup", return_value="广州，气温 20 摄氏度。") as tool, patch(
            "providers.complete"
        ) as complete:
            self.assertEqual(self.ask("天气 广州").json()["tool"], "weather")
            tool.assert_called_once_with("weather", "广州")
            complete.assert_not_called()

    def test_dashboard_assets(self):
        self.assertIn("管理员令牌", self.client.get("/").text)
        self.assertIn("no-store", self.client.get("/dashboard.js").headers["Cache-Control"])

    def test_openrouter_payload_has_zero_price(self):
        response = httpx.Response(200, request=httpx.Request("POST", providers.ENDPOINTS["openrouter"]),
                                  json={"choices": [{"message": {"content": "你好"}}]})
        with patch("providers.httpx.post", return_value=response) as post:
            self.assertEqual(providers.complete("openrouter", "openrouter/free", []), "你好")
            self.assertEqual(post.call_args.kwargs["json"]["provider"]["max_price"],
                             {"prompt": 0, "completion": 0})

    def test_deepseek_paid_gate_and_lifetime_limit(self):
        settings = {"DEEPSEEK_ENABLED": "1", "DEEPSEEK_KEY": "mock",
                    "DEEPSEEK_MODEL": "deepseek-flash", "DEEPSEEK_MODE": "test"}
        with patch.dict(os.environ, settings), patch("providers.complete", return_value="完成") as call:
            self.assertEqual(self.ask("你好").json()["provider"], "groq")
            self.assertNotIn("deepseek", self.client.get("/admin/state", headers=self.admin).json()["models"])
            self.assertEqual(self.ask("DeepSeek：" + "长" * 301).json()["provider"], "local")
            self.assertEqual(call.call_count, 1)
            self.assertEqual(self.ask("DeepSeek：你好", use_history=True, share_memory=True).json()["provider"], "deepseek")
            self.assertEqual(call.call_args.args[2][-1]["content"], "你好")
            self.assertEqual(len(call.call_args.args[2]), 2)
            call.side_effect = httpx.ReadTimeout("mock")
            self.assertIn("不自动重试", self.ask("DeepSeek：测试").json()["speech"])
            self.ask("DeepSeek：测试")
            self.assertIn("额度已用完", self.ask("DeepSeek：测试").json()["speech"])
            self.assertEqual(call.call_count, 4)
            with TestClient(app) as restarted:
                self.assertIn("额度已用完", restarted.post("/ask", headers=self.voice, json={"text": "DeepSeek：测试"}).json()["speech"])
                self.assertEqual(call.call_count, 4)

    def test_deepseek_disabled_by_default_and_no_paid_fallback(self):
        with patch.dict(os.environ, {"DEEPSEEK_ENABLED": "1", "DEEPSEEK_KEY": "mock", "DEEPSEEK_MODEL": "deepseek-flash"}), patch("providers.complete", side_effect=httpx.ReadTimeout("mock")) as call:
            self.assertIn("尚未启用", self.ask("DeepSeek：你好").json()["speech"])
            call.assert_not_called()
            self.assertEqual(self.ask("你好").status_code, 503)
            self.assertEqual([c.args[0] for c in call.call_args_list], ["groq", "openrouter"])

    def test_deepseek_test_payload(self):
        response = httpx.Response(200, request=httpx.Request("POST", providers.ENDPOINTS["deepseek"]),
                                  json={"choices": [{"message": {"content": "你好"}}]})
        with patch.dict(os.environ, {"DEEPSEEK_MODE": "test", "DEEPSEEK_KEY": "mock"}), patch("providers.httpx.post", return_value=response) as post:
            providers.complete("deepseek", "deepseek-flash", [])
            payload = post.call_args.kwargs["json"]
            self.assertEqual(payload["max_tokens"], 128)
            self.assertEqual(payload["thinking"], {"type": "disabled"})

    def test_agent_memory_only_after_confirmation(self):
        import json
        proposal = json.dumps({"answer": "好的", "memory": "我平时喜欢喝茶", "research": []}, ensure_ascii=False)
        with patch("providers.complete", return_value=proposal) as call:
            result = self.ask("我平时喜欢喝茶").json()
            self.assertNotIn("是否记住", result["speech"])
            result = self.ask("我平时喜欢喝茶", share_memory=True).json()
            self.assertIn("是否记住", result["speech"])
            self.assertEqual(self.client.get("/admin/state", headers=self.admin).json()["memory"], [])
            self.assertIn("已保存", self.ask("记下来吧", share_memory=True).json()["speech"])
            self.assertEqual(self.client.get("/admin/state", headers=self.admin).json()["memory"][0]["fact"], "我平时喜欢喝茶")
            self.assertEqual(call.call_count, 2)

    def test_agent_research_and_budget(self):
        import json
        plan = json.dumps({"answer":"待查证", "research":[{"tool":"search","query":"量子计算"}, {"tool":"news","query":"量子计算"}], "memory":""}, ensure_ascii=False)
        evidence = [{"title":"量子计算", "url":"https://zh.wikipedia.org/?curid=1", "snippet":"百科摘要"}]
        with patch("providers.complete", side_effect=[plan, "综合结果"]) as call, patch("app.lookup", return_value=evidence) as lookup:
            result = self.ask("请分析量子计算最新进展").json()
            self.assertEqual(result["answer"], "综合结果")
            self.assertEqual(result["agent_attempts"], 2)
            self.assertEqual(lookup.call_count, 2)
            self.assertEqual(call.call_count, 2)
            self.assertTrue(result["sources"])
            self.assertEqual(self.client.get("/admin/state", headers=self.admin).json()["attempts"], 2)

    def test_agent_blocks_private_query_and_invented_memory(self):
        import json
        import agent
        raw = json.dumps({"answer":"好","research":[{"tool":"news","query":"秘密令牌"},{"tool":"delete","query":"秘密令牌"}],"memory":"我喜欢红茶"}, ensure_ascii=False)
        result = agent.plan(raw, "我的秘密令牌是什么", True)
        self.assertEqual(result.research, [])
        self.assertEqual(result.memory, "")
        self.assertEqual(agent.plan("普通文本", "问题").answer, "普通文本")
        self.assertEqual(agent.plan('{"answer":', "问题").research, [])

    def test_agent_paid_no_automatic_routing(self):
        import json
        raw = json.dumps({"answer":"继续","research":[{"tool":"deepseek","query":"测试"}],"memory":""}, ensure_ascii=False)
        with patch.dict(os.environ, {"DEEPSEEK_MODE":"test","DEEPSEEK_ENABLED":"1","DEEPSEEK_KEY":"mock","DEEPSEEK_MODEL":"deepseek-flash"}), patch("providers.complete", return_value=raw) as call:
            self.assertEqual(self.ask("测试").json()["provider"], "groq")
            self.assertEqual(call.call_count, 1)
            self.assertEqual(self.client.get("/admin/state", headers=self.admin).json()["deepseek_test_used"], 0)

    def test_agent_research_budget_exhaustion(self):
        import json
        raw = json.dumps({"answer":"未查证","research":[{"tool":"search","query":"量子计算"}]}, ensure_ascii=False)
        with patch.dict(os.environ, {"DAILY_ATTEMPTS":"1"}), patch("providers.complete", return_value=raw) as call, patch("app.lookup", return_value=[{"title":"量子计算","url":"https://zh.wikipedia.org/?curid=1"}]):
            result = self.ask("分析量子计算").json()
            self.assertIn("无法综合", result["answer"])
            self.assertEqual(call.call_count, 1)

    def test_rolling_summary_opt_in_restore_and_clear(self):
        import json
        from storage import database
        with database() as db:
            for i in range(12):
                db.execute("INSERT INTO history(question,answer) VALUES (?,?)", ("旧项目记录"+str(i), "讨论"))
        response = json.dumps({"answer":"继续讨论","summary":"用户正在研究旧项目。"}, ensure_ascii=False)
        with patch("providers.complete", return_value=response) as call:
            self.ask("继续", use_history=True)
            self.assertEqual(call.call_count, 1)
            self.assertIn("旧项目记录0", str(call.call_args))
            self.assertEqual(call.call_args.kwargs["max_tokens"], 900)
            self.assertEqual(self.client.get("/admin/state", headers=self.admin).json()["history_summary"], "用户正在研究旧项目。")
            self.ask("新问题")
            self.assertNotIn("用户正在研究旧项目", str(call.call_args))
            self.assertNotIn("旧项目记录", str(call.call_args))
            with TestClient(app) as restarted:
                restarted.post("/ask", headers=self.voice, json={"text":"继续","use_history":True})
                self.assertIn("用户正在研究旧项目", str(call.call_args))
        backup = self.client.get("/admin/backup", headers=self.admin).json()
        self.assertEqual(backup["summary_covered"], 4)
        self.assertEqual(self.client.delete("/admin/history", headers={**self.admin,"X-Confirm":"delete-history"}).status_code, 200)
        self.assertEqual(self.client.get("/admin/state", headers=self.admin).json()["history_summary"], "")
        self.assertEqual(self.client.post("/admin/restore", headers={**self.admin,"X-Confirm":"restore"}, json=backup).status_code, 200)
        self.assertEqual(self.client.get("/admin/backup", headers=self.admin).json()["summary_covered"], 4)
        self.assertEqual(self.client.get("/admin/state", headers=self.admin).json()["history_summary"], "用户正在研究旧项目。")

    def test_stale_history_cannot_resurrect_after_clear(self):
        import continuity
        from storage import database
        with database() as db:
            before = continuity.snapshot(db)
        with database() as db:
            continuity.clear(db)
        with database() as db:
            self.assertFalse(continuity.save(db, before, "旧请求", "旧回答", "旧摘要"))
            self.assertEqual(db.execute("SELECT count(*) FROM history").fetchone()[0], 0)

    def test_summary_is_not_accepted_without_old_turns(self):
        import agent
        self.assertEqual(agent.plan('{"answer":"好","summary":"无来源"}', "你好").summary, "")
        self.assertEqual(agent.plan('{"answer":"好","summary":"有来源"}', "你好", allow_summary=True).summary, "有来源")

    def test_voice_repeat_is_free_and_history_opt_in(self):
        with patch("providers.complete", return_value="茶叶有很多种。") as call:
            self.ask("介绍茶叶", use_history=True)
            self.assertIn("没有开启", self.ask("刚才没听清").json()["speech"])
            self.assertEqual(self.ask("刚才没听清", use_history=True).json()["speech"], "茶叶有很多种。")
            self.assertEqual(self.ask("先聊到这里").json()["provider"], "local")
            self.assertEqual(call.call_count, 1)

    def test_voice_render_does_not_read_links(self):
        import voice
        self.assertEqual(voice.render("参考[资料](https://example.com)。"), "参考资料。")
        speech = voice.render("这是一句完整的话。" * 100)
        self.assertLessEqual(len(speech), 350)
        self.assertNotIn("文字结果", speech)
        self.assertIsNone(voice.timeout_for(20))

    def test_voice_prompt_and_timeout(self):
        with patch("providers.complete", return_value="好。") as call:
            self.ask("你好")
            self.assertIn("家庭音箱", call.call_args.args[2][0]["content"])
            self.assertGreater(call.call_args.kwargs["timeout"], 0)
            self.assertLessEqual(call.call_args.kwargs["timeout"], 12)

if __name__ == "__main__":
    unittest.main()
