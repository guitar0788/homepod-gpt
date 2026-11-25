import Foundation

enum HomeSceneKind: String {
    case welcome, bedtime, tomorrow

    static func parse(_ input: String) -> HomeSceneKind? {
        let text = input.trimmingCharacters(in:.whitespacesAndNewlines)
            .trimmingCharacters(in:CharacterSet(charactersIn:"。！？?!"))
        switch text {
        case "我回来了","我到家了","回家简报","家庭简报","今天过得怎么样": return .welcome
        case "我要睡觉了","准备睡觉","睡前简报","晚安","睡前准备": return .bedtime
        case "帮我安排明天","明日安排","明天有什么安排","明天的计划","明天简报": return .tomorrow
        default: return nil
        }
    }
    var day: String { self == .welcome ? "今天" : "明天" }
    var greeting: String {
        switch self {
        case .welcome: return "欢迎回家。"
        case .bedtime: return "准备休息了。"
        case .tomorrow: return "我们看看明天的安排。"
        }
    }
    var suggestion: String {
        switch self {
        case .welcome: return "可以先休息一下，再处理还没完成的事。"
        case .bedtime: return "可以提前准备明天出门要用的物品，并确认起床闹钟。祝你晚安。"
        case .tomorrow: return "建议先确认固定日程，再留出通勤和休息时间。"
        }
    }
}
