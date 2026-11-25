# 私人助手 iOS 原型

目标：无需用户手工创建快捷指令；在 HomePod 通过 Siri 调用安装在 iPhone 的原生 App Intent，并由 Siri 朗读结果。不是替换 Siri 或独立运行于 HomePod 的 App。

## 构建
在具有支持目标 iOS 版本的 Xcode 的 Mac 上，安装 XcodeGen，进入 ios 目录执行 xcodegen generate，打开生成的 PrivateAssistant.xcodeproj。选择自己的签名 Team 和 iPhone。必要时修改唯一 bundle ID。签名、真机安装以及 SDK 编译未在当前 Linux 环境验证。免费 Personal Team 的签名有期限；TestFlight 需要 Apple Developer Program 会员及相应分发手续。不要将证书、令牌、Apple 账号密码提交到仓库。

## 验收（中文 Siri、美国地区、用户的 iOS 27.3 Beta 1）
1. 安装后先在手机 Siri 说“测试私人助手的连接”，期待固定语音回复。
2. 在 HomePod 重复；检查家庭个人请求、识别我的声音、同一 Apple 账户与网络。手机锁屏重复。
3. 在 HomePod 说“用私人助手测试听写”，等待 Siri 提示，再说无敏感信息的完整句子。确认回读与原句一致。若不能获取自由文本，记录原话和错误，不将该方案标为可用。
4. App 中仅首次粘贴 ASSISTANT_TOKEN 到安全输入框，保存到 Keychain，验证连接。不要输入管理员令牌。初始关闭历史与记忆共享。
5. 对 HomePod 说“询问私人助手”，待提示后提问。验证云端回复由 HomePod 朗读且手机未打开 App。分别测试手机锁屏、首次解锁后的锁屏状态、冷启动和 503/429。
6. 需要记忆共享时由用户在 App 中开启。相关数据可能发送至云端及模型商；有旁人时不要朗读敏感数据。

## 技术状态
原型提供固定回复、听写回显、现有 /ask API 调用三种 App Intent。只使用官方 App Intents、SwiftUI、Security、URLSession，无第三方依赖。没有改动 Render 或主分支。Siri 是否能在指定 Beta 中收集自由文本、锁屏执行和在冷启动超时前完成仍未验证。

Apple 官方参考：
- https://developer.apple.com/videos/play/wwdc2024/10210/
- https://developer.apple.com/documentation/appintents/acceleratingappinteractionswithappintents
- https://developer.apple.com/help/account/basics/about-your-developer-account/

## Health + Home Voice 0.2 实验版

仅本地只读 HealthKit，读取当天步数、步行和跑步距离、活动能量。App 中主动点授权，读取权限以真实查询为准；单独的健康报告 App Intent 要求本机身份验证。健康数据不写入云端、模型或历史。签名需要健康权限 entitlement，免费个人签名是否能保留该能力尚未验证，不购买会员、不替换当前可用 IPA。当前时间/日期在手机本地回答；天气、音乐、音量、闹钟和提醒交给原生 Siri。无法程序化调用任意 Siri 指令或保证 HomePod 代为播放，App 内仅提供正确引导，不宣称完成播放。测试先编译，后验签名、健康权限、锁屏隐私及真实朗读。睡眠心率尚未实现。

## 0.3 家庭服务统一入口

替换上一版天气、音乐转交 Siri 的提示。常见自然语言天气请求在 iPhone 直接调用 Open-Meteo，提供当前气温、体感、今明后天预报和降水概率；默认城市由用户在 App 中设置，也可说出城市。天气只发送城市名到地理编码服务，不调用 AI。时间和日期采用手机本地时区。MusicKit 搜索实际 Apple Music 曲库并通过 SystemMusicPlayer 播放、暂停、切歌、继续；先在 App 授权音乐，曲库播放可能需要现有订阅，不能自动购买。音频输出由 iOS 控制，提供 AVRoutePickerView 选择设备；未保证直接控制 HomePod 自身独立播放队列。闹钟/计时/提醒尚无执行接口，不能声称已设置。健康数据仍独立本机授权，不发送模型。未接入通用意图分类模型，仅覆盖明确常用说法。真实设备签名、音乐权限、播放和 HomePod 路由仍须验证。

## 0.4 Siri 增强层

保留系统 Siri 的原生指令入口，不拦截 Siri 或修改其系统能力。增强助手入口新增基于 Open-Meteo 预报的出门、带伞、穿衣等建议，修复日期位于城市前的天气问法；建议为确定性规则，不使用模型。按睡前、放松、运动、专注场景选择 MusicKit 曲库搜索关键词，组成最多8首的播放队列；不是人工精选，也不保证适合所有用户。未改动 HealthKit 权限和云端预算。没有接入系统闹钟、日程或提醒执行，也不能让系统 Siri 自动将所有问句路由到此 App。编译与真机验收需分开。
