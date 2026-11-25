import Foundation

enum NativeHome {
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
        if let result = await HomeWeather.reply(text) { return result }
        if let result = await HomeMusic.reply(text) { return result }
        if text.hasPrefix("设置闹钟") || text.hasPrefix("设个闹钟") || text.hasPrefix("设置计时器") || text.hasPrefix("提醒我") {
            return "这个版本还没有接入闹钟、计时器或提醒事项执行接口。"
        }
        if ["今日健康报告", "今天的健康报告", "我的健康数据", "我今天走了多少步", "今天走了多少步", "我今天消耗了多少卡路里", "我今天走了多远"].contains(text) {
            return "请使用私人助手的今日健康报告功能，系统会要求本机身份验证。健康记录不会发送到 AI 云端。"
        }
        return nil
    }
}
