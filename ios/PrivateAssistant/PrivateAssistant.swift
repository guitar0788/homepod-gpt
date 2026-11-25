import SwiftUI
import AppIntents
import Security
import Foundation

// Personal device only. Never put a server token in the source or a build setting.
enum TokenStore {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.homepodgpt.privateassistant",
        kSecAttrAccount as String: "voice-token"
    ]

    static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) -> Bool {
        let data = Data(token.utf8)
        let update = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(query as CFDictionary, update)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = query
        item[kSecValueData as String] = data
        // Available after first unlock following reboot; not backed up to another device.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func clear() -> Bool {
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

enum AssistantAPI {
    struct Body: Encodable {
        let text: String
        let use_history: Bool
        let share_memory: Bool
    }
    struct Reply: Decodable { let speech: String }

    static func ask(_ text: String) async -> String {
        if let local = await NativeHome.reply(text) { return local }
        guard let token = TokenStore.read(), token.count >= 32 else {
            return "请先在 iPhone 的私人助手中保存语音令牌。"
        }
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, question.count <= 3000 else { return "请提供有效的问题。" }
        var request = URLRequest(url: URL(string: "https://homepod-gpt.onrender.com/ask")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 65
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let defaults = UserDefaults.standard
        do {
            request.httpBody = try JSONEncoder().encode(Body(
                text: question,
                use_history: defaults.bool(forKey: "useHistory"),
                share_memory: defaults.bool(forKey: "shareMemory")
            ))
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "服务器响应异常。" }
            switch http.statusCode {
            case 200:
                return try JSONDecoder().decode(Reply.self, from: data).speech
            case 401: return "语音令牌无效，请在手机上重新配置。"
            case 429: return "请求过于频繁或免费额度已用完。"
            case 503: return "云端服务暂时不可用，请稍后再试。"
            default: return "服务器返回错误，请稍后再试。"
            }
        } catch {
            // No request body, token or upstream payload is logged.
            return "连接失败，服务可能正在冷启动。请稍后重试。"
        }
    }
}

// Isolate Siri routing and voice output from free-text recognition and networking.
struct ProbeIntent: AppIntent {
    static let title: LocalizedStringResource = "测试连接"
    static let openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "私人助手的语音接入测试成功。")
    }
}

struct EchoIntent: AppIntent {
    static let title: LocalizedStringResource = "测试听写"
    static let openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "测试句子", requestValueDialog: "请说一句不含个人信息的测试句子。")
    var phrase: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "我听到的是：\(phrase)")
    }
}

struct AskIntent: AppIntent {
    static let title: LocalizedStringResource = "询问私人助手"
    static let openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "问题", requestValueDialog: "你想问什么？")
    var question: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let speech = await AssistantAPI.ask(question)
        return .result(dialog: "\(speech)")
    }
}

struct PrivateAssistantShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ProbeIntent(),
                    phrases: ["测试 \(.applicationName) 的连接"],
                    shortTitle: "测试连接", systemImageName: "checkmark.circle")
        AppShortcut(intent: EchoIntent(),
                    phrases: ["用 \(.applicationName) 测试听写"],
                    shortTitle: "测试听写", systemImageName: "mic")
        AppShortcut(intent: AskIntent(),
                    phrases: ["询问 \(.applicationName)", "用 \(.applicationName) 提问"],
                    shortTitle: "询问", systemImageName: "bubble.left")
        AppShortcut(intent: HealthReportIntent(),
                    phrases: ["用 \(.applicationName) 查看今日健康报告", "查看 \(.applicationName) 的健康报告"],
                    shortTitle: "今日健康", systemImageName: "heart.text.square")
        AppShortcut(intent: HomePrivateTasksIntent(), phrases: ["用 \(.applicationName) 管理日程与提醒", "使用 \(.applicationName) 的家庭日程"], shortTitle: "日程与提醒", systemImageName: "calendar")
        AppShortcut(intent: WelcomeSceneIntent(), phrases: ["用 \(.applicationName) 查看回家简报", "查看 \(.applicationName) 的家庭简报"], shortTitle: "回家简报", systemImageName: "house")
        AppShortcut(intent: BedtimeSceneIntent(), phrases: ["用 \(.applicationName) 查看睡前简报"], shortTitle: "睡前简报", systemImageName: "moon")
        AppShortcut(intent: TomorrowSceneIntent(), phrases: ["用 \(.applicationName) 安排明天"], shortTitle: "明日安排", systemImageName: "calendar.badge.clock")
    }
}

@main
struct PrivateAssistantApp: App {
    var body: some Scene {
        WindowGroup { SettingsView() }
    }
}

struct SettingsView: View {
    @State private var token = ""
    @State private var status = ""
    @State private var configured = false
    @State private var checking = false
    @State private var healthStatus = ""
    @State private var musicStatus = ""
    @State private var taskStatus = ""
    @AppStorage("homeWeatherCity") private var homeWeatherCity = ""
    @AppStorage("useHistory") private var useHistory = false
    @AppStorage("shareMemory") private var shareMemory = false
    @AppStorage("sceneCalendar") private var sceneCalendar = false
    @AppStorage("sceneReminders") private var sceneReminders = false
    @AppStorage("sceneHealth") private var sceneHealth = false
    @State private var sceneStatus = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("首次连接") {
                    Text(configured ? "已保存语音令牌" : "尚未保存语音令牌")
                    SecureField("粘贴 ASSISTANT_TOKEN", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存语音令牌") {
                        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard value.count >= 32 else { status = "令牌长度无效。"; return }
                        configured = TokenStore.save(value)
                        status = configured ? "已安全保存。" : "保存失败。"
                        if configured { token = "" }
                    }
                    Button("验证服务器连接") {
                        checking = true
                        Task {
                            status = await AssistantAPI.ask("查看模型")
                            checking = false
                        }
                    }.disabled(!configured || checking)
                    Button("移除本机令牌", role: .destructive) {
                        let removed = TokenStore.clear()
                        configured = TokenStore.read() != nil
                        status = removed ? "已移除。" : "移除失败。"
                    }
                    if !status.isEmpty { Text(status) }
                }
                Section("记忆与隐私") {
                    Toggle("使用近期对话", isOn: $useHistory)
                    Toggle("共享匹配记忆", isOn: $shareMemory)
                    Text("默认关闭。开启后相关内容可能发送给模型。HomePod 可在手机锁屏时尝试运行语音操作，请勿在他人可听见时读取敏感记忆。")
                        .font(.footnote)
                }
                Section("Apple 健康（本机只读）") {
                    Button("授权 Apple 健康") { Task { healthStatus = await LocalHealth.authorize() } }
                    Button("查看今日健康报告") { Task { healthStatus = await LocalHealth.report() } }
                    if !healthStatus.isEmpty { Text(healthStatus) }
                    Text("仅读取步数、步行和跑步距离、活动能量、睡眠和心率记录。不会写入健康数据、上传云端或保存报告。语音报告需要本机身份验证，请留意旁人能听见。").font(.footnote)
                }
                Section("家庭服务") {
                    TextField("默认天气城市（例如北京）", text: $homeWeatherCity)
                    Button("授权 Apple Music") { Task { musicStatus = await HomeMusic.authorize() } }
                    if !musicStatus.isEmpty { Text(musicStatus) }
                    HStack { Text("选择音频输出"); Spacer(); HomeAudioRoutePicker().frame(width: 44, height: 44) }
                    Text("Siri 原有功能不受影响。进入增强助手后，可以问明天适不适合出门、要不要带伞，或要求睡前音乐。音乐由系统播放器执行；HomePod 音频路由需真机验证。").font(.footnote)
                }
                Section("家庭日程与提醒") {
                    Button("授权日历读取") { Task { taskStatus = await HomeTasks.authorizeCalendar() } }
                    Button("授权提醒事项") { Task { taskStatus = await HomeTasks.authorizeReminders() } }
                    Button("授权手机计时通知") { Task { taskStatus = await HomeTasks.authorizeNotifications() } }
                    Button("授权系统闹钟") { Task { taskStatus = await HomeAlarm.authorize() } }
                    if !taskStatus.isEmpty { Text(taskStatus) }
                    Text("日程和提醒使用独立的本机身份验证语音入口；不上传云端。计时提醒由 iPhone 通知发出，不会保证 HomePod 响铃。").font(.footnote)
                }
                Section("家庭场景简报") {
                    Toggle("简报包含日历日程", isOn: $sceneCalendar)
                    Toggle("简报包含到期待办", isOn: $sceneReminders)
                    Toggle("回家简报包含健康记录", isOn: $sceneHealth)
                    Button("预览公开回家简报") { Task { sceneStatus = await HomeScenes.report(.welcome,privateAccess:false) } }
                    if !sceneStatus.isEmpty { Text(sceneStatus) }
                    Text("三项私人数据默认关闭，开启后仍需单项系统授权及本机身份验证。简报不会自动播放音乐、写入日历、设置闹钟或上传私人数据。").font(.footnote)
                }
                Section("HomePod 测试") {
                    Text("先说：嘿 Siri，测试私人助手的连接。")
                    Text("再说：嘿 Siri，用私人助手测试听写。")
                    Text("最后说：嘿 Siri，询问私人助手。")
                    Text("测试版：是否能在 HomePod 上接收自由文本、锁屏执行及朗读，须使用实际设备验证。")
                        .font(.footnote)
                }
            }
            .navigationTitle("私人助手")
            .onAppear { configured = TokenStore.read() != nil }
        }
    }
}
