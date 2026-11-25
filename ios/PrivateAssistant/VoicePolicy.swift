import Foundation

enum VoicePolicy {
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in:.whitespacesAndNewlines)
            .trimmingCharacters(in:CharacterSet(charactersIn:"。！？?!"))
            .trimmingCharacters(in:.whitespacesAndNewlines)
    }
    static func privateDestination(_ raw: String) -> String? {
        let text = normalize(raw)
        if ["日程","日历","提醒我","提醒事项","待办","明天有什么安排"].contains(where:{text.contains($0)}) {
            // The separately authenticated entry is always required for personal records.
            return "请使用私人助手的家庭日程与提醒功能，进行本机身份验证。"
        }
        let healthTerms = ["我的血氧","我的体重","我的体脂","我的BMI","我的呼吸频率","我的运动记录","我的饮水记录","详细健康报告","我的健康","我的心率","我的静息心率","我的睡眠","我的步数","健康报告","健康记录","健康数据","我今天走","今天走了多少步","我今天消耗","我昨晚睡","昨晚睡了多久","今天心率","昨晚的睡眠","今天睡了多久"]
        if healthTerms.contains(where:{text.contains($0)}) {
            return "请使用私人助手的今日健康报告功能，进行本机身份验证。"
        }
        return nil
    }
    static func hasActionCue(_ text: String) -> Bool {
        ["播放","放音乐","放歌","放一首","放首","放点","放些","来一首","来点","来些","听音乐","听歌","切歌","下一首","上一首","暂停","恢复音乐","继续音乐","停止音乐","闹钟","计时","叫醒","叫我起床"].contains(where:{text.contains($0)})
    }
    static func blocksAction(_ raw: String) -> Bool {
        let text = normalize(raw)
        guard hasActionCue(text) else { return false }
        return ["不要","不用","别","不必","不需要","禁止","如果","假如","假设","例如","举例","假装","能不能","可不可以","是否可以","如何","怎么","为什么","原理","是什么","教程","写代码","先别","除非","等我","之后再","然后再","再过","测试一下"].contains(where:{text.contains($0)})
    }
    static func musicQueryAllowed(_ raw: String) -> Bool {
        let text = normalize(raw)
        guard !text.isEmpty, text.count <= 100, !blocksAction(text) else { return false }
        // Requests to hear an explanation or a story must not be treated as song titles.
        return !["解释","讲讲","讲一个","讲个","故事","笑话","新闻","天气","日程","分析","建议","朗读","读一下","说说","你说","你的看法","告诉我","怎么","如何","为什么"].contains(where:{text.contains($0)})
    }
}
