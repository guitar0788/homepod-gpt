import Foundation
func check(_ ok: @autoclosure () -> Bool,_ label: String) {
    if !ok() { fatalError(label) }
}
let both = HomeReadPlan(weather:true,clock:true,day:"明天",city:"北京",advice:true)
let utterance = "告诉我现在几点，以及明天北京天气"
check(ReadRouting.compound(utterance),"compound")
check(ReadRouting.validated(both,input:utterance) != nil,"valid")
check(ReadRouting.validated(both,input:"现在几点以及明天天气") == nil,"invented city")
check(ReadRouting.validated(both,input:"不要查明天北京天气，现在几点") == nil,"negation")
check(ReadRouting.validated(both,input:"明天北京天气怎么样，帮我设置闹钟") == nil,"write exclusion")
check(ReadRouting.validated(both,input:"我的地址是北京，明天天气，现在几点") == nil,"private")
let missing = HomeReadPlan(weather:true,clock:false,day:"明天",city:"北京",advice:false)
check(ReadRouting.validated(missing,input:utterance) == nil,"missing tool")
let wrongDay = HomeReadPlan(weather:true,clock:true,day:"今天",city:"北京",advice:false)
check(ReadRouting.validated(wrongDay,input:utterance) == nil,"incorrect date")
let single = HomeReadPlan(weather:true,clock:false,day:"明天",city:"",advice:false)
check(ReadRouting.validated(single,input:"明天出门要不要带伞")?.advice == nil,"negation guard conservatively rejects")
check(ReadRouting.validated(single,input:"明天出门需要带伞吗")?.advice == true,"weather advice")
print("10 read routing checks passed")
