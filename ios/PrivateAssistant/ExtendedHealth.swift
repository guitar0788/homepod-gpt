import Foundation
import HealthKit
import AppIntents

// Optional grouped, read-only data access; never uploads or persists samples.
enum ExtendedHealth {
    enum Group: String, CaseIterable, Identifiable {
        case activity, heart, body, lifestyle
        var id: String { rawValue }
        var title: String {
            switch self {
            case .activity: return "活动与体能"
            case .heart: return "心脏与呼吸"
            case .body: return "身体测量"
            case .lifestyle: return "听力与营养"
            }
        }
    }
    struct Metric {
        let id: HKQuantityTypeIdentifier
        let title: String
        let unit: HKUnit
        let suffix: String
        let sum: Bool
        let scale: Double
        let precision: Int
        init(_ id: HKQuantityTypeIdentifier,_ title:String,_ unit:HKUnit,_ suffix:String, sum:Bool = false, scale:Double = 1, precision:Int = 1) {
            self.id=id; self.title=title; self.unit=unit; self.suffix=suffix; self.sum=sum; self.scale=scale; self.precision=precision
        }
    }
    private static let store = HKHealthStore()
    static func metrics(_ group: Group) -> [Metric] {
        switch group {
        case .activity: return [
            Metric(.stepCount,"步数",.count(),"步",sum:true,precision:0),
            Metric(.distanceWalkingRunning,"步行及跑步距离",.meterUnit(with:.kilo),"公里",sum:true),
            Metric(.activeEnergyBurned,"活动能量",.kilocalorie(),"千卡",sum:true,precision:0),
            Metric(.basalEnergyBurned,"静息能量",.kilocalorie(),"千卡",sum:true,precision:0),
            Metric(.flightsClimbed,"爬楼层数",.count(),"层",sum:true,precision:0),
            Metric(.appleExerciseTime,"运动时间",.minute(),"分钟",sum:true,precision:0),
            Metric(.vo2Max,"最大摄氧量",HKUnit(from:"mL/kg*min"),"毫升每公斤每分钟"),
            Metric(.walkingSpeed,"步行速度",HKUnit.meter().unitDivided(by:.second()),"米每秒"),
            Metric(.walkingStepLength,"步长",.meterUnit(with:.centi),"厘米")
        ]
        case .heart: return [
            Metric(.heartRate,"心率",HKUnit.count().unitDivided(by:.minute()),"次每分钟",precision:0),
            Metric(.restingHeartRate,"静息心率",HKUnit.count().unitDivided(by:.minute()),"次每分钟",precision:0),
            Metric(.heartRateVariabilitySDNN,"心率变异性",.secondUnit(with:.milli),"毫秒"),
            Metric(.walkingHeartRateAverage,"步行平均心率",HKUnit.count().unitDivided(by:.minute()),"次每分钟",precision:0),
            Metric(.oxygenSaturation,"血氧饱和度",.percent(),"%",scale:100),
            Metric(.respiratoryRate,"呼吸频率",HKUnit.count().unitDivided(by:.minute()),"次每分钟")
        ]
        case .body: return [
            Metric(.height,"身高",.meterUnit(with:.centi),"厘米"),
            Metric(.bodyMass,"体重",.gramUnit(with:.kilo),"公斤"),
            Metric(.bodyMassIndex,"BMI",.count(),""),
            Metric(.bodyFatPercentage,"体脂率",.percent(),"%",scale:100)
        ]
        case .lifestyle: return [
            Metric(.environmentalAudioExposure,"环境音量",.decibelAWeightedSoundPressureLevel(),"分贝"),
            Metric(.headphoneAudioExposure,"耳机音量",.decibelAWeightedSoundPressureLevel(),"分贝"),
            Metric(.dietaryWater,"饮水记录",.literUnit(with:.milli),"毫升",sum:true,precision:0),
            Metric(.dietaryEnergyConsumed,"膳食能量记录",.kilocalorie(),"千卡",sum:true,precision:0)
        ]
        }
    }
    static func authorize(_ group: Group) async -> String {
        guard HKHealthStore.isHealthDataAvailable() else { return "此设备不支持 Apple 健康。" }
        let types = Set<HKObjectType>(metrics(group).compactMap{HKObjectType.quantityType(forIdentifier:$0.id)})
        do {
            try await store.requestAuthorization(toShare:[],read:types)
            return "\(group.title)授权流程已完成。实际可读取项目以查询结果为准。"
        } catch {
            let e=error as NSError
            return "健康授权失败：\(e.domain)，\(e.code)。"
        }
    }
    static func read(_ metric:Metric, start:Date,end:Date) async -> String? {
        guard let type = HKObjectType.quantityType(forIdentifier:metric.id) else { return nil }
        if metric.sum {
            return await withCheckedContinuation { continuation in
                let predicate = HKQuery.predicateForSamples(withStart:start,end:end,options:.strictStartDate)
                let query = HKStatisticsQuery(quantityType:type,quantitySamplePredicate:predicate,options:.cumulativeSum) { _,stats,error in
                    guard error == nil, let value = stats?.sumQuantity()?.doubleValue(for:metric.unit), value.isFinite else {
                        continuation.resume(returning:nil); return
                    }
                    continuation.resume(returning:"\(metric.title)今日合计\(String(format:"%.*f",metric.precision,value*metric.scale))\(metric.suffix)")
                }
                store.execute(query)
            }
        }
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart:nil,end:end,options:.strictEndDate)
            let query = HKSampleQuery(sampleType:type,predicate:predicate,limit:1,sortDescriptors:[NSSortDescriptor(key:HKSampleSortIdentifierEndDate,ascending:false)]) { _,samples,error in
                guard error == nil, let sample = samples?.first as? HKQuantitySample else { continuation.resume(returning:nil); return }
                let value=sample.quantity.doubleValue(for:metric.unit)
                guard value.isFinite else { continuation.resume(returning:nil); return }
                let date=DateFormatter()
                date.locale=Locale(identifier:"zh_CN"); date.dateFormat="yyyy年M月d日 HH:mm"
                continuation.resume(returning:"\(metric.title)\(String(format:"%.*f",metric.precision,value*metric.scale))\(metric.suffix)（\(date.string(from:sample.endDate))记录）")
            }
            store.execute(query)
        }
    }
    static func report(_ group:Group) async -> String {
        guard HKHealthStore.isHealthDataAvailable() else { return "此设备不支持 Apple 健康。" }
        let end=Date(),start=Calendar.current.startOfDay(for:end)
        let results = await withTaskGroup(of:(Int,String?).self) { tasks in
            for (index,metric) in metrics(group).enumerated() {
                tasks.addTask { (index,await read(metric,start:start,end:end)) }
            }
            var items:[(Int,String?)]=[]
            for await value in tasks { items.append(value) }
            return items.sorted{$0.0 < $1.0}
        }
        let available=results.compactMap{$0.1}
        let missing=results.count-available.count
        return "\(group.title)：读取到\(available.count)项，\(missing)项没有可读取记录。" + (available.isEmpty ? "" : available.joined(separator:"；")+"。") + "数据不代表实时测量或医学判断。"
    }
}
struct ExtendedHealthIntent: AppIntent {
    static let title: LocalizedStringResource = "详细健康报告"
    static let openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    @Parameter(title:"分类",requestValueDialog:"要查看活动与体能、心脏与呼吸、身体测量，还是听力与营养？")
    var category:String
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let group = ExtendedHealth.Group.allCases.first { $0.title == category.trimmingCharacters(in:.whitespacesAndNewlines) }
        guard let group else { return .result(dialog:"请选择活动与体能、心脏与呼吸、身体测量或听力与营养。") }
        let result=await ExtendedHealth.report(group)
        return .result(dialog:"\(result)")
    }
}
