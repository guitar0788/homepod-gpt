import Foundation

// This is a read-only dispatcher. It never constructs a write or playback command.
struct HomeReadPlan {
    let weather: Bool
    let clock: Bool
    let day: String
    let city: String
    let advice: Bool
}
enum ReadRouting {
    static func weatherCue(_ s: String) -> Bool {
        ["天气","气温","下雨","下雪","带伞","穿衣","穿什么","冷不冷","热不热","出门","出去玩","户外","散步","跑步"].contains(where: { s.contains($0) })
    }
    static func clockCue(_ s: String) -> Bool {
        ["几点","现在时间","当前时间","现在的时间","时间是多少","几时"].contains(where: { s.contains($0) })
    }
    static func eligible(_ s: String) -> Bool {
        guard s.count <= 180, weatherCue(s) || clockCue(s) else { return false }
        let blocked = ["不要","不用","别","取消","停止","删除","设置","提醒","闹钟","计时","叫我","叫醒","播放","音乐","听歌","放歌","健康","心率","睡眠","步数","病","药","日程","日历","密码","密钥","令牌","住址","地址","账号","电话","身份证","@","http","sk-","忽略","指令","假装","执行","为什么","原理","定义","是什么","翻译","写一","编一"]
        return !blocked.contains(where: { s.contains($0) })
    }
    static func compound(_ s: String) -> Bool { eligible(s) && weatherCue(s) && clockCue(s) }
    static func validated(_ plan: HomeReadPlan, input: String) -> HomeReadPlan? {
        guard eligible(input), plan.weather || plan.clock else { return nil }
        guard !plan.weather || weatherCue(input), !plan.clock || clockCue(input) else { return nil }
        // A compound request must not silently drop one of the explicitly requested services.
        if compound(input) && !(plan.weather && plan.clock) { return nil }
        let city = plan.city.trimmingCharacters(in:.whitespacesAndNewlines)
        if plan.weather && !city.isEmpty {
            guard city.count >= 2, city.count <= 24, input.localizedCaseInsensitiveContains(city),
                  city.range(of:#"^[\p{Han}A-Za-z ]+$"#,options:.regularExpression) != nil,
                  !["我","你","的","今天","明天","后天","时间","天气","这里","当地","家里","本地","请","查","说","想","知道"].contains(where:{ city.contains($0) }) else { return nil }
        }
        let day = input.contains("后天") ? "后天" : input.contains("明天") ? "明天" : "今天"
        guard !plan.weather || plan.day == day else { return nil }
        let advice = ["带伞","穿衣","穿什么","出门","出去玩","户外","散步","跑步"].contains(where:{input.contains($0)})
        return HomeReadPlan(weather:plan.weather,clock:plan.clock,day:day,city:plan.weather ? city : "",advice:plan.weather && advice)
    }
}
