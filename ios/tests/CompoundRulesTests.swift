import Foundation
func check(_ value: @autoclosure () -> Bool, _ label: String) { if !value() { fatalError(label) } }
check(HomeCompoundRules.parse("现在几点，然后查一下明天北京天气") == .plan([.time("现在几点"),.weather("查一下明天北京天气")]),"two reads")
check(HomeCompoundRules.parse("现在几点，顺便设置五分钟计时器") == .plan([.time("现在几点"),.timer("设置五分钟计时器")]),"one action")
check(HomeCompoundRules.parse("明天天气，然后明天早上七点叫我起床") == .plan([.weather("明天天气"),.alarm("明天早上七点叫我起床")]),"alarm")
check(HomeCompoundRules.parse("现在几点，然后播放周杰伦的歌") == .plan([.time("现在几点"),.music("播放周杰伦的歌")]),"music")
check(HomeCompoundRules.parse("现在几点，然后不要播放音乐") == .unsupported,"negation")
check(HomeCompoundRules.parse("现在几点，然后播放音乐，然后设置五分钟计时器") == .unsupported,"two actions")
check(HomeCompoundRules.parse("现在几点，然后查看我的日历") == .unsupported,"private")
check(HomeCompoundRules.parse("现在几点，然后播放音乐的原理是什么") == .unsupported,"discussion not action")
check(HomeCompoundRules.parse("苹果和香蕉有什么区别") == .none,"ordinary question")
check(HomeCompoundRules.parse("现在几点，然后现在几点") == .unsupported,"duplicate")
print("10 compound routing checks passed")
