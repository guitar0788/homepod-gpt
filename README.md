# HomePod GPT

HomePod mini → Siri 快捷指令 → HTTPS FastAPI → 模型服务。iPhone 使用苹果听写及朗读动作，云端处理文本。长期记忆、可选近期对话、模型首选项和调用预算存入 PostgreSQL。

## 本地启动

要求 Python 3.11 及以上。

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export ASSISTANT_TOKEN="$(python -c 'import secrets; print(secrets.token_urlsafe(32))')"
export ADMIN_TOKEN="$(python -c 'import secrets; print(secrets.token_urlsafe(32))')"
export LOCAL_SQLITE=1
uvicorn app:app --host 127.0.0.1 --port 8000 --no-access-log
```

本地管理页为 http://127.0.0.1:8000/。使用终端私下读取管理员令牌。模型环境变量见 `.env.example`，依部署平台填写，在本地启动前 export。配置完成后重启进程。

```bash
python -m unittest -v
python scripts/smoke.py
node --check web/dashboard.js
```

## 模型与隐私

- 仅允许免费路由。初始优先顺序为 Groq、Gemini、OpenRouter。语音或网页可设首选，失败后最多试一个替代服务。Groq/Gemini 必须先验证项目未启用计费及具体模型确在免费层，再填写对应 `VERIFIED_FREE_MODELS`。启用和切换具体模型 ID 分别通过环境变量和管理页完成。
- OpenRouter 仅允许 `openrouter/free` 或 `:free` 模型，附带零价上限与拒绝数据收集参数。免费账户对策略参数的实时兼容性需要实测。可采用一个明确的 `:free` ID 验证。OpenAI 和 DeepSeek 的兼容端点已定义，免费模式拒绝直接调用两者。
- 每分钟最多 12 次语音请求，每 UTC 日默认 35 次模型尝试。失败和回退均消耗尝试次数。面板显示应用计数；账单以服务商和托管控制台为准。
- Render 随请求处理输入。配置并启用的模型提供商可收到当次问题。如果发生回退，另一个服务商也可能收到相同输入。OpenRouter 会将输入转发给其实际推理提供商。
- 只有开启 `use_history` 才发送最近五轮并保存本轮，最多保留最近三十轮。只有开启 `share_memory` 才发送最多四条匹配记忆。只有开启 `share_context` 才发送请求中的 `context`。渲染层本身仍会收到发给 API 的字段，因此敏感数据须在 iPhone 上先筛选并确认。
- 天气、新闻及搜索分别向 Open-Meteo、Google News RSS 和中文 Wikipedia 发送查询。搜索覆盖百科索引，新闻覆盖 RSS 返回的标题与链接。当前工具由指定前缀或 `tool` 参数触发，模型没有自主操作设备的权限。
- Google Gemini 免费层可能使用内容改进产品，适合先用无个人信息的问题验证。Groq 保留使用元数据，推理内容适用其数据控制规则。备份含明文记忆与对话，存到用户控制的加密位置。

## iPhone 快捷指令安装

详见 [iPhone 快捷指令](SHORTCUTS.md)。从 iPhone 手动创建，验证后才在 Siri/HomePod 调用。没有签名的可导入文件。

## 部署与维护

详见 [交付与验收](DELIVERY.md)。正常启动只接受 PostgreSQL，TLS 含服务器证书校验。方括号内的值替换为后台所提示的合法值。从私有仓库部署，Render 选择 Free Web Service，填入 `render.yaml` 对应设置。服务端持有模型密钥和数据库凭据，iPhone 只持有语音令牌。切勿共享含令牌的快捷指令、截图或备份。

在管理页连接后可以筛选、添加、修改及删除记忆，选择首选模型，下载备份、清除对话或将备份恢复到空库。默认只展示最新 100 条匹配记录，完整导出包含所有条目。备份覆盖记忆与对话，恢复后重新设置首选项，重新配置各项密钥。若需完整保留数据库对象和 ID，请使用受控连接执行 PostgreSQL 的 `pg_dump` 和 `pg_restore`，先恢复到独立数据库验证。

每次变更前运行单元测试和本地重启测试。上线后依次验证 `/health`、`/ready`、未授权 401、免费模型调用、记忆保存和重启后的检索。定期检查免费服务政策和用量，轮换令牌后同步更新 iPhone。Render 冷启动超时后，先用 Safari 打开 HTTPS `/health` 等待服务恢复，再重试语音操作。故障期间不要反复发送未经确认的写入请求。
