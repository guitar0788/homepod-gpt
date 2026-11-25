# HomePod GPT 交付与验收

日期为 2026 年 11 月 25 日（北京时间）。

## 交付状态

| 验收项 | 状态 |
|---|---|
| API、网页及配置 | 已在项目中实现，网页静态资源通过测试 |
| 鉴权、速率限制、免费预算和付费阻断 | 本地自动测试通过 |
| 模型语音切换与超时回退 | 模拟上游测试通过 |
| 长期记忆及重启 | 本地 SQLite，两个独立 Uvicorn 进程验证通过 |
| 记忆编辑、检索、确认删除、导出及恢复 | 本地 API 测试通过 |
| 查询工具 | 使用模拟天气验证路由，新闻、百科以及实际天气端点未做线上验证 |
| PostgreSQL 与云端部署 | 已部署到 Render My Workspace；`/health`、`/ready` 均返回 `{"ok":true}`，管理员页面可读取持久化记忆 |
| 私有 GitHub 仓库 | 已创建 `guitar0788/homepod-gpt`（private） |
| 真实免费模型及云端故障恢复 | Gemini `gemini-3.1-flash-lite` 已成功回答一次无个人信息的测试问题；此前日志有一次 HTTP 503，未复现。备用模型缺少密钥，尚未验证回退 |
| iPhone 17 | 提供手动安装与权限配置，设备未验证 |
| HomePod mini | 到货后做实机验收 |

现有 V2 的主要缺口是没有管理员角色和速率预算，手动指定模型时无故障回退，近期记忆会默认发送给模型，清除对话无需确认，HTTP 200 掩盖部分服务异常。当前版本保留 /ask 与旧表，增加管理员令牌，改变了历史与记忆默认共享行为。旧数据库如已存在，部署前备份；现有记忆、历史可继续读取。

当前只适用于单人家庭使用。模型工具调用为显式的只读查询；尚无模型驱动多步 Agent、设备写入或邮件操作。OpenAI 和 DeepSeek 兼容端点在当前的免费模式中禁用。

## 免费部署比较

| 服务 | 已核实的免费条件及限制 | 账户级待确认 |
|---|---|---|
| Render Free Web Service | 每月每工作区 750 免费实例小时；15 分钟无流量后休眠，唤醒约一分钟；文件系统临时；无付款方式时用尽流量会暂停，耗尽构建额度会禁用新构建 | 现有工作区是否绑定付款方式、具体配额、超额保护和私有仓库授权 |
| Neon Free | 官方更新列出每项目 100 CU 小时/月、1 GB 存储及 5 GB 公网传输，闲置 5 分钟停止计算，6 小时恢复窗口。恢复窗口指可回滚的历史，不等同于数据寿命。公网端点需要凭据和 TLS；IP Allow 属于 Scale | 账户信用卡要求、超额及长期闲置项目处理，以控制台当日条款为准 |
| Render Free Postgres | 可走同区域内部网络，但免费实例 30 天后到期，存在随后删除的期限，长期记忆不采用此版本 | 无 |
| GroqCloud | 有免费率限制，依模型与组织而异；通常不保留推理内容，但保留元数据及例外条款 | 实际可用模型、未绑定计费、地区及数据控制设置 |
| Gemini | 部分模型免费，地区和项目额度不同。Google 免费层可能将内容用于产品改善 | 账户可用地区、模型及未启用计费 |
| OpenRouter | 免费变体不需要购买额度，未充值时通常是每分钟 20 次、每天 50 次，失败也计入 | 不加付款方式/充值，核对上游政策、检查零价及数据路由参数受支持 |
| OpenAI / DeepSeek | 官方列出的直接 API 价格按使用计量 | 免费模式保持禁用 |

正规配置需要在账号页面复核付款方式与条款。若既要求数据库端口不经过公网，又坚持零费用，应先确定能提供持久私网数据库的免费组合。若用户接受可从公网到达、但仅允许经身份验证及 TLS 访问的数据库端点，再配置 Neon。也可使用已有的私网 PostgreSQL。当前已创建 Render Free Web Service，并连接外部 PostgreSQL；本次未创建或升级付费云端资源。

官方资料：
- [Render 免费条款](https://render.com/docs/free) · [Render 隐私政策](https://render.com/privacy)
- [Neon 免费规格](https://neon.com/blog/neon-free-plan-1-gb-per-project) · [历史恢复窗口](https://github.com/neondatabase/website/blob/main/content/docs/postgres/backup-restore/history-window.md) · [IP 限制](https://neon.com/blog/restrict-access-to-your-neon-database-with-ip-allow) · [Neon 隐私政策更新](https://neon.com/blog/we-updated-our-privacy-policy)
- [Groq 数据控制](https://console.groq.com/docs/your-data) · [Groq 速率限制](https://console.groq.com/docs/rate-limits)
- [Gemini 定价及数据处理](https://ai.google.dev/gemini-api/docs/pricing)
- [OpenRouter 免费模型和额度](https://openrouter.ai/collections/free-models/) · [OpenRouter 数据处理协议](https://openrouter.ai/assets/data-processing-agreement.pdf)
- [OpenAI 定价](https://platform.openai.com/pricing/) · [DeepSeek 定价](https://api-docs.deepseek.com/quick_start/pricing/)
- [苹果 Siri 快捷指令](https://support.apple.com/guide/shortcuts/run-shortcuts-with-siri-apd07c25bb38/ios) · [苹果 HomePod 个人请求](https://support.apple.com/guide/homepod/make-personal-content-requests-apde0a4edb55/homepod) · [苹果 HomePod 温湿度](https://support.apple.com/en-ie/guide/homepod/apd8085c1032/homepod)

## 线上验收记录模板

以无个人信息的样例测试。记录 HTTPS 地址、私库地址、模型名、时间、状态码和是否回退。避免记录密钥、个人日程或对话内容。先测试一个免费模型，再启用第二个免费模型。测试库中临时撤下首选模型密钥或使其不可用，确认回退后恢复设置。将限额调为 1，确认额外请求返回 429，再恢复正常限额。保存测试记忆，重启服务，确认 ID 与内容存在。最后在管理页确认删除测试记忆。

## 2026-11-25 线上验收补记（北京时间）

- 服务地址：https://homepod-gpt.onrender.com/；Render 工作区：My Workspace；服务 `srv-dc386q8u01pc73dseeu0`，Free，Singapore。
- 已确认 `ASSISTANT_TOKEN`、`ADMIN_TOKEN` 在 Render 环境中存在、长度符合应用要求且互不相同；令牌值未写入仓库或此文档。管理员连接成功。
- `/health`、`/ready` 均返回 `{"ok":true}`；测试问题“一加一等于几？”收到 Gemini `gemini-3.1-flash-lite` 回答。此前日志显示 Gemini HTTP 503 一次；现有证据只说明本次调用成功，不能排除间歇性上游故障。
- 新建测试记忆“线上持久化验收 20261125-B”；对同一提交触发重新部署 `dep-dc3cr1nlot8c739q78n0`，状态 live 后重新连接管理页，确认该记录和旧记录“云端重启验收 20261125-A”均可读。两条测试记录目前保留在数据库中。
- 管理页仅列出 Gemini；Render 环境变量列表未显示 `OPENROUTER_KEY` 或 Groq 配置，因此尚无法实际验证免费备用模型及回退。须在对应供应商确认账户免费额度、模型与隐私设置，安全配置密钥后再进行无个人信息的回退测试。
- 未在现有非空生产库上执行“恢复到空数据库”操作；备份恢复应使用独立空库验证。iPhone 快捷指令与 HomePod mini 尚待设备端安装及实机验收，步骤见 `SHORTCUTS.md`。

## DeepSeek 付费测试（独立于免费路由）

默认关闭。Render 安全环境变量设置 DEEPSEEK_ENABLED=1、DEEPSEEK_MODEL=deepseek-flash、DEEPSEEK_MODE=test，DEEPSEEK_KEY 仅在 Render 存放。语音说“DeepSeek：你的问题”或 API 显式指定 provider=deepseek。测试总共三次尝试（数据库永久计数，失败也计入），每次输入最多300字符、输出128 tokens、关闭思考；不共享历史、记忆或上下文，不自动重试、不自动回退到付费模型。正式启用须另行将 DEEPSEEK_MODE 改为 production，默认日上限35次，仍须显式调用，正式版完整记忆接入待升级。配置不等于真实调用验收。密钥不得提交。

## Agent V2 beta（独立分支）

使用免费模型的结构化规划结果判断是否需要研究，并提出需要明确确认的原文记忆；仅在现有 App 开启记忆共享时提供候选记忆及建议。最多2次免费模型尝试（包括失败/回退/综合），最多2项固定端点公开主题查询。检索为本地候选排序加模型语义理解，尚非向量检索；研究仅百科摘要与新闻标题，不能阅读任意网页或进行全面事实核验。保持单人、只读工具边界，无后台任务和设备控制。原有 DeepSeek 三次总测试预算不变，不允许 Agent 自动调用。所有新增测试使用模拟模型与工具；真实 Gemini JSON 遵循能力、延迟和 HomePod 实机尚待验收。待确认记忆保存在进程内，重启或5分钟后失效；存储前须明确确认，过滤规则不能保证识别全部敏感数据。
