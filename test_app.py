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

if __name__ == "__main__":
    unittest.main()
