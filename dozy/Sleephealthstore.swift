//
//  Sleephealthstore.swift
//  dozy
//
//  Created by Charvi Bansal on 6/6/26.
//

import Foundation
import HealthKit


/// Thin wrapper around HealthKit for reading sleep-stage data.
/// Everything here runs on-device. No backend.
final class SleepHealthStore {

    static let shared = SleepHealthStore()
    private let store = HKHealthStore()

    private init() {}

    // MARK: - Authorization

    /// HealthKit may be unavailable on iPad / unsupported hardware.
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Request read access to sleep analysis. We also request WRITE access so a
    /// completed nap can be logged back to Health (real recovery data).
    func requestAuthorization() async throws {
        guard isAvailable else { throw SleepError.healthDataUnavailable }
        let sleepType = HKCategoryType(.sleepAnalysis)
        var read: Set<HKObjectType> = [sleepType]
        read.formUnion(Self.signalTypes)
        try await store.requestAuthorization(toShare: [sleepType], read: read)
    }

    // MARK: - Overnight signals

    /// What a watch measures while you sleep, besides the stages themselves.
    private static let signalTypes: [HKQuantityType] = [
        HKQuantityType(.heartRate),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.respiratoryRate),
    ]

    /// Average heart rate (bpm), heart rate variability (ms) and breathing rate
    /// (breaths/min) between two moments. A value is nil when Health has nothing for
    /// that window, which is also what a declined permission looks like.
    func overnightSignals(start: Date, end: Date) async -> (heartRate: Double?, hrv: Double?, breathing: Double?) {
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        async let heartRate = average(.heartRate, unit: perMinute, start: start, end: end)
        async let hrv = average(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: start, end: end)
        async let breathing = average(.respiratoryRate, unit: perMinute, start: start, end: end)
        return await (heartRate, hrv, breathing)
    }

    private func average(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit,
                         start: Date, end: Date) async -> Double? {
        guard isAvailable, end > start else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(identifier),
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                continuation.resume(returning: statistics?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Log a completed nap as asleep time so it counts toward recovery and
    /// syncs across the user's devices via Apple Health.
    func logNap(start: Date, end: Date) async throws {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let sample = HKCategorySample(
            type: sleepType,
            value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            start: start, end: end
        )
        try await store.save(sample)
    }

    // MARK: - Background updates

    private var sleepObserver: HKObserverQuery?

    /// Runs `onChange` whenever new sleep data is written to Health, waking the app in
    /// the background if needed. Needs the HealthKit background-delivery entitlement.
    func observeSleep(onChange: @escaping () async -> Void) {
        guard isAvailable, sleepObserver == nil else { return }
        let sleepType = HKCategoryType(.sleepAnalysis)

        let query = HKObserverQuery(sampleType: sleepType, predicate: nil) { _, completion, error in
            if error != nil {
                // Usually Health access hasn't been granted yet. Allow a later retry.
                completion()
                Task { @MainActor in SleepHealthStore.shared.sleepObserver = nil }
                return
            }
            Task { @MainActor in
                await onChange()
                completion()   // tells HealthKit this update has been handled
            }
        }
        sleepObserver = query
        store.execute(query)
        store.enableBackgroundDelivery(for: sleepType, frequency: .immediate) { _, _ in }
    }

    // MARK: - Raw fetch

    /// Fetch all sleep-analysis samples in [start, end).
    /// Returns samples sorted by start date ascending.
    func fetchSleepSamples(start: Date, end: Date) async throws -> [HKCategorySample] {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: [.strictStartDate]
        )
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let samples = (results as? [HKCategorySample]) ?? []
                continuation.resume(returning: samples)
            }
            store.execute(query)
        }
    }
}

enum SleepError: LocalizedError {
    case healthDataUnavailable
    case notAuthorized
    case noData

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable: return "Health data isn't available on this device."
        case .notAuthorized: return "Dozy needs permission to read your sleep data."
        case .noData: return "No sleep data found yet. Wear your watch overnight and check back."
        }
    }
}
