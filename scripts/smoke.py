"""Restart a real local HTTP server twice using one database file."""
import os
import socket
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from secrets import token_urlsafe

import httpx

@contextmanager
def server(port, env):
    process = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "app:app", "--host", "127.0.0.1",
         "--port", str(port), "--no-access-log", "--log-level", "warning"], env=env
    )
    try:
        with httpx.Client(base_url=f"http://127.0.0.1:{port}", timeout=2, trust_env=False) as client:
            for _ in range(100):
                if process.poll() is not None:
                    raise RuntimeError("Server exited")
                try:
                    if client.get("/ready").status_code == 200:
                        break
                except httpx.TransportError:
                    pass
                time.sleep(0.05)
            else:
                raise RuntimeError("Server did not become ready")
            yield client
    finally:
        process.terminate()
        process.wait(timeout=10)

def main():
    with tempfile.TemporaryDirectory() as directory, socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
        listener.close()
        env = {**os.environ, "LOCAL_SQLITE": "1", "SQLITE_PATH": directory + "/smoke.db",
               "DATABASE_URL": "", "ASSISTANT_TOKEN": token_urlsafe(32),
               "ADMIN_TOKEN": token_urlsafe(32)}
        env.pop("RENDER", None)
        voice = {"Authorization": "Bearer " + env["ASSISTANT_TOKEN"]}
        admin = {"Authorization": "Bearer " + env["ADMIN_TOKEN"]}
        with server(port, env) as client:
            assert client.post("/ask", json={"text": "查看模型"}).status_code == 401
            assert client.post("/ask", headers=voice, json={"text": "记住：本地重启测试"}).status_code == 200
        with server(port, env) as client:
            response = client.get("/admin/state", headers=admin)
            assert response.status_code == 200
            assert response.json()["memory"][0]["fact"] == "本地重启测试"
        print("PASS: HTTP authentication and memory persistence across two independent processes")

if __name__ == "__main__":
    main()
