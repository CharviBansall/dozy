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
        try await store.requestAuthorization(toShare: [sleepType], read: [sleepType])
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
