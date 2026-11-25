import Foundation
import EventKit
import UserNotifications
import AppIntents

enum HomeTasks {
    static func match(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { i in
            Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }

    static func number(_ s: String) -> Int? {
        if let n = Int(s) { return n }
        let digits: [Character:Int] = ["零":0,"一":1,"二":2,"两":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9]
        if s == "半" { return nil }
        if s == "十" { return 10 }
        if let i = s.firstIndex(of: "十") {
            let left = String(s[..<i]), right = String(s[s.index(after:i)...])
            guard left.count <= 1, right.count <= 1,
                  let a = left.isEmpty ? 1 : left.first.flatMap({digits[$0]}),
                  let b = right.isEmpty ? 0 : right.first.flatMap({digits[$0]}) else { return nil }
            return a*10+b
        }
        return s.count == 1 ? s.first.flatMap{digits[$0]} : nil
    }

    static func timerSeconds(_ text: String) -> Int? {
        let n = "[0-9零一二两三四五六七八九十]{1,4}"
        let pattern = "^(?:帮我)?(?:设置|设个|设一个|设|开始)?(?:一个)?(?:计时器|倒计时|计时)?\\s*(" + n + ")(秒钟|秒|分钟|分|小时|钟头)(?:的)?(?:计时器|倒计时|计时)?$"
        guard let groups = match(pattern,text), let value = number(groups[0]), value > 0, value <= 86400,
              text.contains("计时") else { return nil }
        let multiplier = groups[1].hasPrefix("秒") ? 1 : (groups[1] == "分" || groups[1] == "分钟") ? 60 : 3600
        let seconds = value*multiplier
        return seconds <= 86400 ? seconds : nil
    }

    static func authorizeNotifications() async -> String {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert,.sound])
            return granted ? "手机计时通知已授权。" : "没有获得通知权限。"
        } catch { return "通知授权失败。" }
    }

    static func timer(_ text: String) async -> String? {
        if ["取消计时器","取消倒计时","取消计时"].contains(text) {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers:["home-timer"])
            return "已取消本助手的手机计时提醒。"
        }
        guard let seconds = timerSeconds(text) else { return nil }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return "请先在助手 App 授权计时通知。"
        }
        let content = UNMutableNotificationContent()
        content.title = "家庭助手计时结束"
        content.body = "你设置的计时已结束。"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(seconds), repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier:"home-timer", content:content,trigger:trigger))
            return "已在 iPhone 设置\(seconds)秒计时提醒。它会通过手机通知提醒，不是 HomePod 的原生计时器。"
        } catch { return "计时提醒未能设置成功。" }
    }

    static func authorizeCalendar() async -> String {
        do {
            let ok = try await EKEventStore().requestFullAccessToEvents()
            return ok ? "日历读取已授权。" : "日历读取未授权。"
        } catch { return "日历授权失败。" }
    }

    static func authorizeReminders() async -> String {
        do {
            let ok = try await EKEventStore().requestFullAccessToReminders()
            return ok ? "提醒事项已授权。" : "提醒事项未授权。"
        } catch { return "提醒事项授权失败。" }
    }

    static func isPrivate(_ text: String) -> Bool {
        text.contains("日程") || text.contains("日历") || text.contains("提醒我") || text.contains("提醒事项")
    }

    static func calendarReport(_ text: String) -> String {
        guard EKEventStore.authorizationStatus(for:.event) == .fullAccess else { return "请在助手 App 中授权日历读取。" }
        let store = EKEventStore()
        let calendar = Calendar.current
        let offset = text.contains("后天") ? 2 : text.contains("明天") ? 1 : 0
        let start = calendar.date(byAdding:.day,value:offset,to:calendar.startOfDay(for:Date()))!
        let end = calendar.date(byAdding:.day,value:1,to:start)!
        let events = store.events(matching:store.predicateForEvents(withStart:start,end:end,calendars:nil)).sorted{$0.startDate < $1.startDate}
        let label = offset == 2 ? "后天" : offset == 1 ? "明天" : "今天"
        if events.isEmpty { return "\(label)没有读取到日历事件。" }
        let format = DateFormatter()
        format.locale = Locale(identifier:"zh_CN")
        format.dateFormat = "HH点mm分"
        let details = events.prefix(6).map { e in
            (e.isAllDay ? "全天" : format.string(from:e.startDate)) + "，" + String((e.title ?? "未命名").prefix(80))
        }.joined(separator:"；")
        return "\(label)共有\(events.count)项日程。" + details + (events.count > 6 ? "。还有其他日程未朗读。" : "。")
    }

    static func createReminder(_ text: String) -> String {
        guard EKEventStore.authorizationStatus(for:.reminder) == .fullAccess else { return "请在助手 App 中授权提醒事项。" }
        let n = "[0-9零一二两三四五六七八九十]{1,4}"
        let pattern = "^(?:帮我)?(" + n + ")(分钟|小时)后提醒我(.+)$"
        guard let parts = match(pattern,text), let amount = number(parts[0]), amount > 0, amount <= 1440 else {
            return "目前支持明确的相对时间，例如十分钟后提醒我喝水。没有设置提醒。"
        }
        let seconds = amount * (parts[1] == "小时" ? 3600 : 60)
        let title = parts[2].trimmingCharacters(in:.whitespacesAndNewlines)
        guard seconds <= 604800, !title.isEmpty, title.count <= 150 else { return "提醒时间或内容不符合范围，未设置。" }
        let store = EKEventStore()
        guard let list = store.defaultCalendarForNewReminders() else { return "没有可写入的默认提醒事项列表。" }
        let item = EKReminder(eventStore:store)
        item.title = title
        item.calendar = list
        let due = Date().addingTimeInterval(Double(seconds))
        item.dueDateComponents = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second],from:due)
        item.addAlarm(EKAlarm(absoluteDate:due))
        do {
            try store.save(item,commit:true)
            return "已在提醒事项添加：\(parts[0])\(parts[1])后，\(title)。"
        } catch { return "提醒事项保存失败，没有确认设置成功。" }
    }
}

struct HomePrivateTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "家庭日程与提醒"
    static let openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    @Parameter(title:"任务",requestValueDialog:"你想查看哪天的日程，或设置什么提醒？")
    var task: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = task.trimmingCharacters(in:.whitespacesAndNewlines).trimmingCharacters(in:CharacterSet(charactersIn:"。！？?!"))
        let result: String
        if text.contains("提醒我") { result = HomeTasks.createReminder(text) }
        else if text.contains("日程") || text.contains("日历") { result = HomeTasks.calendarReport(text) }
        else { result = "请说今天或明天的日程，或者明确的相对时间提醒。" }
        return .result(dialog:"\(result)")
    }
}
