import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
check(HomeSceneKind.parse("我回来了。") == .welcome, "welcome")
check(HomeSceneKind.parse("我要睡觉了") == .bedtime, "bedtime")
check(HomeSceneKind.parse("帮我安排明天") == .tomorrow, "tomorrow")
check(HomeSceneKind.parse("我想了解睡眠的科学") == nil, "ordinary conversation")
check(HomeSceneKind.parse("明天早上七点叫我起床") == nil, "do not intercept alarms")
check(HomeSceneKind.parse("不要帮我安排明天") == nil, "negation")
check(HomeSceneKind.welcome.day == "今天" && HomeSceneKind.bedtime.day == "明天", "date routing")
print("7 scene routing checks passed")
