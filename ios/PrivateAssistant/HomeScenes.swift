import Foundation
import AppIntents

enum HomeScenes {
    static func report(_ kind: HomeSceneKind, privateAccess: Bool) async -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier:"zh_CN")
        formatter.dateFormat = "HH点mm分"
        var parts = [kind.greeting + "现在是\(formatter.string(from:Date()))。"]
        // City is the only user-supplied input transmitted to the weather provider.
        if let weather = await HomeWeather.reply(kind.day + "怎么穿衣服") {
            parts.append(weather)
        }
        if privateAccess {
            let preferences = UserDefaults.standard
            if preferences.bool(forKey:"sceneCalendar") {
                parts.append(HomeTasks.calendarReport(kind.day + "日程"))
            }
            if preferences.bool(forKey:"sceneReminders") {
                parts.append(await HomeTasks.pendingReport(kind.day))
            }
            if kind == .welcome && preferences.bool(forKey:"sceneHealth") {
                parts.append(await LocalHealth.report())
            }
        } else {
            parts.append("如需加入个人日程、待办或健康记录，可以使用家庭简报的身份验证入口。")
        }
        parts.append(kind.suggestion)
        return parts.joined(separator:" ")
    }
}

struct WelcomeSceneIntent: AppIntent {
    static let title: LocalizedStringResource = "回家简报"
    static let openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await HomeScenes.report(.welcome,privateAccess:true)
        return .result(dialog:"\(result)")
    }
}
struct BedtimeSceneIntent: AppIntent {
    static let title: LocalizedStringResource = "睡前简报"
    static let openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await HomeScenes.report(.bedtime,privateAccess:true)
        return .result(dialog:"\(result)")
    }
}
struct TomorrowSceneIntent: AppIntent {
    static let title: LocalizedStringResource = "明日安排"
    static let openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await HomeScenes.report(.tomorrow,privateAccess:true)
        return .result(dialog:"\(result)")
    }
}
