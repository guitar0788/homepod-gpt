import Foundation

enum HomeCompoundRules {
    enum Part: Equatable {
        case time(String), weather(String), alarm(String), timer(String), music(String)
        var action: Bool {
            switch self { case .alarm, .timer, .music: return true; default: return false }
        }
        var kind: String {
            switch self {
            case .time: return "time"
            case .weather: return "weather"
            case .alarm: return "alarm"
            case .timer: return "timer"
            case .music: return "music"
            }
        }
        var phrase: String {
            switch self {
            case .time(let s), .weather(let s), .alarm(let s), .timer(let s), .music(let s): return s
            }
        }
    }
    enum Result: Equatable { case none, unsupported, plan([Part]) }

    static func classify(_ raw: String) -> Part? {
        let text = raw.trimmingCharacters(in:.whitespacesAndNewlines)
            .trimmingCharacters(in:CharacterSet(charactersIn:"。！？?!"))
        if text.isEmpty || text.count > 100 { return nil }
        let forbidden = ["不要","不用","别","取消","停止","删除","如果","假如","假设","例如","假装","忽略","密码","密钥","令牌","住址","地址","账号","电话","身份证","健康","心率","睡眠记录","步数","日历","日程","提醒","@","http","sk-"]
        guard !forbidden.contains(where:{text.contains($0)}) else { return nil }
        if ["几点了","现在几点","现在几点了","现在时间","现在是什么时间","现在的时间","告诉我现在几点","告诉我现在几点了","查一下现在几点"].contains(text) { return .time(text) }
        if text.contains("闹钟") || text.hasSuffix("叫我起床") || text.hasSuffix("叫醒我") {
            return .alarm(text)
        }
        if text.contains("计时") { return .timer(text) }
        if ["暂停音乐","暂停播放","下一首","上一首","切歌","继续播放","继续音乐","恢复播放","播放音乐","放音乐"].contains(text) { return .music(text) }
        let musicPrefixes = ["帮我播放","给我播放","播放","放一首","放首","来一首","放点","放些","来点","来些"]
        if musicPrefixes.contains(where:{text.hasPrefix($0)}) && !["怎么","如何","能不能","可以吗","是什么","什么是","为什么","闹钟","计时","时间","天气"].contains(where:{text.contains($0)}) {
            return .music(text)
        }
        if ReadRouting.eligible(text) && ReadRouting.weatherCue(text) && !ReadRouting.clockCue(text) {
            return .weather(text)
        }
        return nil
    }
    static func parse(_ input: String) -> Result {
        let text = input.trimmingCharacters(in:.whitespacesAndNewlines)
        let separator = #"\s*(?:[，,；;]\s*(?:然后|顺便|并且|同时|以及|再帮我|再)?|然后|顺便|并且|同时|以及)\s*"#
        guard let regex = try? NSRegularExpression(pattern:separator) else { return .none }
        let marked = regex.stringByReplacingMatches(in:text,range:NSRange(text.startIndex...,in:text),withTemplate:"\u{001F}")
        let clauses = marked.components(separatedBy:"\u{001F}").map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}
        guard clauses.count > 1 else { return .none }
        let parts = clauses.compactMap(classify)
        // Only intercept combinations that include a recognizable household service.
        let hints = ["闹钟","叫我起床","叫醒我","计时","播放","切歌","下一首","音乐","放点","放些","来点","来些","日程","日历","提醒"]
        let hasHint = ReadRouting.weatherCue(text) || ReadRouting.clockCue(text) || hints.contains(where:{text.contains($0)})
        guard hasHint else { return .none }
        guard clauses.count <= 3, text.count <= 260, parts.count == clauses.count,
              parts.filter({$0.action}).count <= 1, Set(parts.map{$0.kind}).count == parts.count else {
            return .unsupported
        }
        return .plan(parts)
    }
}
