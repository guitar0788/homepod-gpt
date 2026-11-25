import Foundation

enum HomeCompound {
    static func valid(_ parts: [HomeCompoundRules.Part]) -> Bool {
        for part in parts {
            switch part {
            case .time: break
            case .weather(let text):
                guard HomeWeather.parse(text) != nil else { return false }
            case .alarm(let text):
                guard HomeAlarm.parse(text) != nil else { return false }
            case .timer(let text):
                guard HomeTasks.timerSeconds(text) != nil else { return false }
            case .music(let text):
                // The music executor still independently validates authorization and query.
                guard !text.isEmpty, text.count <= 100 else { return false }
            }
        }
        return true
    }

    static func execute(_ parts: [HomeCompoundRules.Part]) async -> String {
        var answers: [String] = []
        // Read-only operations first; at most one explicitly requested, confirmed action.
        for part in parts.filter({!$0.action}) + parts.filter({$0.action}) {
            let result: String?
            switch part {
            case .time: result = "现在是" + NativeHome.localTime() + "。"
            case .weather(let text): result = await HomeWeather.reply(text)
            case .alarm(let text): result = await HomeAlarm.reply(text)
            case .timer(let text): result = await HomeTasks.timer(text)
            case .music(let text): result = await HomeMusic.reply(text)
            }
            answers.append(result ?? "未能执行：" + part.phrase + "。")
        }
        return answers.joined(separator:" ")
    }
}
