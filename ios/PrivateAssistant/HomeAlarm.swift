import Foundation
import SwiftUI
import AlarmKit

@available(iOS 26.0, *)
struct HomeAlarmMetadata: AlarmMetadata {
    let purpose: String
}

enum HomeAlarm {
    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let n = "[0-9零一二两三四五六七八九十]{1,4}"
        let pattern = "^(?:帮我)?(?:设置|设个|设一个|设)?(今天|明天|后天)(凌晨|早上|上午|中午|下午|晚上)?(" + n + ")(?:点|时)(?:(" + n + ")分?)?(半)?(?:的)?(?:闹钟|叫我起床|叫醒我|叫我)$"
        guard let p = HomeTasks.match(pattern,text), let rawHour = HomeTasks.number(p[2]),
              (0...23).contains(rawHour), !(p[3] != "" && p[4] != "") else { return nil }
        var hour = rawHour
        if !p[1].isEmpty {
            guard (1...12).contains(rawHour) else { return nil }
            if ["下午","晚上"].contains(p[1]) { hour = rawHour % 12 + 12 }
            else if p[1] == "中午" {
                guard rawHour == 12 || rawHour == 1 else { return nil }
                hour = rawHour % 12 + 12
            } else { hour = rawHour % 12 }
        } else if rawHour < 13 {
            // Avoid silently guessing morning versus evening.
            return nil
        }
        let minute = p[4] == "半" ? 30 : p[3].isEmpty ? 0 : (HomeTasks.number(p[3]) ?? -1)
        guard (0...59).contains(minute) else { return nil }
        let offset = p[0] == "后天" ? 2 : p[0] == "明天" ? 1 : 0
        guard let day = calendar.date(byAdding:.day,value:offset,to:calendar.startOfDay(for:now)),
              let date = calendar.date(bySettingHour:hour,minute:minute,second:0,of:day,matchingPolicy:.strict),
              calendar.isDate(date,inSameDayAs:day), date > now else { return nil }
        return date
    }

    @MainActor static func authorize() async -> String {
        guard #available(iOS 26.0, *) else { return "系统闹钟需要 iOS 26 或更新版本。" }
        guard let reason = Bundle.main.object(forInfoDictionaryKey:"NSAlarmKitUsageDescription") as? String, !reason.isEmpty else {
            return "安装包缺少闹钟权限声明，请更新 App。"
        }
        let manager = AlarmManager.shared
        if manager.authorizationState == .authorized { return "家庭助手闹钟权限已授权。" }
        if manager.authorizationState == .denied { return "闹钟权限已被拒绝，请在系统设置中的本 App 权限页面重新开启（如系统提供）。" }
        do {
            let state = try await manager.requestAuthorization()
            return state == .authorized ? "家庭助手闹钟权限已授权。" : "没有获得闹钟权限。请检查系统设置。"
        } catch {
            let e = error as NSError
            return "闹钟权限请求失败。错误域：\(e.domain)，代码：\(e.code)。请提供该错误信息。"
        }
    }

    @MainActor static func reply(_ text: String) async -> String? {
        guard text.contains("闹钟") || text.hasSuffix("叫我起床") || text.hasSuffix("叫醒我") || text.hasSuffix("叫我") else { return nil }
        guard #available(iOS 26.0, *) else { return "系统闹钟需要 iOS 26 或更新版本，未设置。" }
        guard let date = parse(text) else { return "请明确日期和上午或下午，例如明天早上七点叫我起床。没有设置闹钟。" }
        let manager = AlarmManager.shared
        guard manager.authorizationState == .authorized else { return "请先在助手 App 授权系统闹钟。没有设置闹钟。" }
        let stop = AlarmButton(text:"停止",textColor:.white,systemImageName:"stop.circle")
        let presentation = AlarmPresentation(alert:AlarmPresentation.Alert(title:"家庭助手闹钟",stopButton:stop))
        let attributes = AlarmAttributes(presentation:presentation,metadata:HomeAlarmMetadata(purpose:"wake"),tintColor:.blue)
        let config = AlarmManager.AlarmConfiguration<HomeAlarmMetadata>.alarm(schedule:.fixed(date),attributes:attributes)
        do {
            // Bound this app's outstanding alarms, and refuse duplicate schedules when possible.
            let existing = try manager.alarms
            guard existing.count < 20 else { return "家庭助手的闹钟数量已达上限，请先管理已有闹钟。" }
            let id = UUID()
            _ = try await manager.schedule(id:id,configuration:config)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier:"zh_CN")
            formatter.dateFormat = "M月d日 HH点mm分"
            return "已在 iPhone 设置家庭助手闹钟，\(formatter.string(from:date))。由手机系统响铃，不保证 HomePod 响铃。"
        } catch { return "系统闹钟未能设置成功。" }
    }
}
