import Foundation

enum NativeHome {
    static func localTime() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier:"zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "HH点mm分"
        return formatter.string(from:Date())
    }
    static func reply(_ input: String) async -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "。？！?！!"))
        if ["几点了", "现在几点", "现在几点了", "现在时间", "现在是什么时间", "今天几号", "今天星期几", "今天是几号", "今天是什么日期"].contains(text) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.timeZone = .current
            formatter.dateFormat = text.hasPrefix("今天") ? "yyyy年M月d日 EEEE" : "HH点mm分"
            return formatter.string(from: Date())
        }
        if let scene = HomeSceneKind.parse(text) { return await HomeScenes.report(scene,privateAccess:false) }
        if ReadRouting.compound(text) {
            if let result = await SmartHome.reply(text) { return result }
            return "现在是" + localTime() + "。天气部分请单独说出城市和日期；本机智能调度暂时不可用。"
        }
        if let result = await HomeWeather.reply(text) { return result }
        if let result = await HomeMusic.reply(text) { return result }
        if let result = await HomeAlarm.reply(text) { return result }
        if let result = await HomeTasks.timer(text) { return result }
        if HomeTasks.isPrivate(text) { return "请使用本助手的家庭日程与提醒功能进行本机身份验证，日程及提醒内容不会发送云端。" }
        if text.contains("闹钟") || text.contains("计时") { return "暂不支持此闹钟或计时表达。可以说设置五分钟计时器；该功能使用手机通知，不是系统闹钟。" }
        if ["今日健康报告", "今天的健康报告", "我的健康数据", "我今天走了多少步", "今天走了多少步", "我今天消耗了多少卡路里", "我今天走了多远"].contains(text) {
            return "请使用私人助手的今日健康报告功能，系统会要求本机身份验证。健康记录不会发送到 AI 云端。"
        }
        if let result = await SmartHome.reply(text) { return result }
        return nil
    }
}
