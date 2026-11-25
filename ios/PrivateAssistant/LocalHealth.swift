import Foundation
import HealthKit
import AppIntents

// The app never transmits HealthKit samples or summaries to the remote API.
enum LocalHealth {
    private static let store = HKHealthStore()
    private static let metrics: [(HKQuantityTypeIdentifier, HKUnit, String)] = [
        (.stepCount, .count(), "步"),
        (.distanceWalkingRunning, .meterUnit(with: .kilo), "公里"),
        (.activeEnergyBurned, .kilocalorie(), "千卡")
    ]

    static func authorize() async -> String {
        guard HKHealthStore.isHealthDataAvailable() else { return "此设备不支持 Apple 健康。" }
        var types: Set<HKObjectType> = Set(metrics.compactMap { HKObjectType.quantityType(forIdentifier: $0.0) })
        for id in [HKQuantityTypeIdentifier.heartRate, .restingHeartRate] {
            if let type = HKObjectType.quantityType(forIdentifier:id) { types.insert(type) }
        }
        if let type = HKObjectType.categoryType(forIdentifier:.sleepAnalysis) { types.insert(type) }
        do {
            try await store.requestAuthorization(toShare: [], read: types)
            return "授权流程已完成。能否读取各项数据，以实际查询结果为准。"
        } catch {
            return "未能完成 Apple 健康授权。请检查 App 签名权限和系统健康设置。"
        }
    }

    private static func total(_ type: HKQuantityType, unit: HKUnit, start: Date, end: Date) async -> Double? {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                guard error == nil else { continuation.resume(returning: nil); return }
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private static func latest(_ identifier: HKQuantityTypeIdentifier, start: Date, end: Date) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier:identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart:start,end:end,options:.strictStartDate)
            let query = HKSampleQuery(sampleType:type,predicate:predicate,limit:1,
                sortDescriptors:[NSSortDescriptor(key:HKSampleSortIdentifierEndDate,ascending:false)]) { _, samples, error in
                guard error == nil, let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning:nil); return
                }
                let value = sample.quantity.doubleValue(for:HKUnit.count().unitDivided(by:.minute()))
                continuation.resume(returning:value.isFinite && value > 0 ? value : nil)
            }
            store.execute(query)
        }
    }

    // Union overlapping asleep intervals; never count the same recorded minutes twice.
    private static func sleepMinutes(start: Date,end: Date) async -> Int? {
        guard end > start, let type = HKObjectType.categoryType(forIdentifier:.sleepAnalysis) else { return nil }
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart:start,end:end,options:[])
            let query = HKSampleQuery(sampleType:type,predicate:predicate,limit:10000,sortDescriptors:nil) { _,samples,error in
                guard error == nil, let samples = samples as? [HKCategorySample], samples.count < 10000 else {
                    continuation.resume(returning:nil); return
                }
                let asleep = Set([HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue])
                let intervals = samples.filter { asleep.contains($0.value) }.map {
                    (max(start,$0.startDate),min(end,$0.endDate))
                }.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
                guard var merged = intervals.first else { continuation.resume(returning:nil); return }
                var seconds: TimeInterval = 0
                for interval in intervals.dropFirst() {
                    if interval.0 <= merged.1 { merged.1 = max(merged.1,interval.1) }
                    else { seconds += merged.1.timeIntervalSince(merged.0); merged = interval }
                }
                seconds += merged.1.timeIntervalSince(merged.0)
                continuation.resume(returning:Int((seconds/60).rounded()))
            }
            store.execute(query)
        }
    }

    static func report() async -> String {
        guard HKHealthStore.isHealthDataAvailable() else { return "此设备不支持 Apple 健康。" }
        let end = Date()
        let start = Calendar.current.startOfDay(for: end)
        var parts: [String] = []
        for (identifier, unit, label) in metrics {
            guard let type = HKObjectType.quantityType(forIdentifier: identifier),
                  let value = await total(type, unit: unit, start: start, end: end),
                  value.isFinite, value >= 0 else { continue }
            let name = identifier == .stepCount ? "步数" : identifier == .distanceWalkingRunning ? "步行和跑步距离" : "活动能量"
            let precision = identifier == .distanceWalkingRunning ? 1 : 0
            parts.append("\(name)\(String(format: "%.*f", precision, value))\(label)")
        }
        async let heart = latest(.heartRate,start:start,end:end)
        async let resting = latest(.restingHeartRate,start:start,end:end)
        let calendar = Calendar.current
        if let yesterday = calendar.date(byAdding:.day,value:-1,to:start),
           let evening = calendar.date(bySettingHour:18,minute:0,second:0,of:yesterday),
           let noon = calendar.date(bySettingHour:12,minute:0,second:0,of:start),
           let sleep = await sleepMinutes(start:evening,end:min(noon,end)) {
            parts.append("昨晚至今天中午记录的睡眠\(sleep/60)小时\(sleep%60)分钟")
        }
        if let value = await heart { parts.append("今日最近一次心率记录约每分钟\(Int(value.rounded()))次") }
        if let value = await resting { parts.append("今日最近一次静息心率记录约每分钟\(Int(value.rounded()))次") }
        guard !parts.isEmpty else {
            return "暂时没有可读取的今日健康记录。请解锁 iPhone，检查健康权限及数据来源。"
        }
        return "今天 Apple 健康记录：" + parts.joined(separator: "，") + "。这是已记录的数据，可能尚未同步完整；不代表实时测量或医疗判断。"
    }
}

struct HealthReportIntent: AppIntent {
    static let title: LocalizedStringResource = "今日健康报告"
    static let openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await LocalHealth.report()
        return .result(dialog: "\(result)")
    }
}
