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
        let types: Set<HKObjectType> = Set(metrics.compactMap { HKObjectType.quantityType(forIdentifier: $0.0) })
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
        guard !parts.isEmpty else {
            return "暂时没有可读取的今日健康记录。请解锁 iPhone，检查健康权限及数据来源。"
        }
        return "今天 Apple 健康记录：" + parts.joined(separator: "，") + "。这是已记录的数据，可能尚未同步完整。"
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
