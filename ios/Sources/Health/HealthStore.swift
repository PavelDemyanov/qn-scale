import Foundation
import HealthKit

/// Запись веса в «Здоровье» и импорт истории оттуда.
@Observable
@MainActor
final class HealthStore {

    struct ImportResult {
        var found = 0
        var imported = 0
        var skipped = 0
        var earliest: Date?
    }

    private let store = HKHealthStore()
    private(set) var isAuthorized = false

    private var shareTypes: Set<HKQuantityType> {
        Set([HKQuantityType(.bodyMass),
             HKQuantityType(.bodyFatPercentage),
             HKQuantityType(.leanBodyMass),
             HKQuantityType(.bodyMassIndex)])
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: [HKQuantityType(.bodyMass)])
            isAuthorized = true
        } catch {
            isAuthorized = false
        }
        return isAuthorized
    }

    /// Пишет одно взвешивание.
    func save(weighIn: WeighIn, profile: Profile, enabled: Bool) async {
        guard enabled, isAvailable else { return }
        if !isAuthorized { _ = await requestAuthorization() }

        var samples: [HKQuantitySample] = []
        let date = weighIn.date

        samples.append(HKQuantitySample(
            type: HKQuantityType(.bodyMass),
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weighIn.weightKg),
            start: date, end: date))

        if let composition = weighIn.composition(for: profile), !composition.fatPercent.isNaN {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.bodyFatPercentage),
                quantity: HKQuantity(unit: .percent(), doubleValue: composition.fatPercent / 100),
                start: date, end: date))
            samples.append(HKQuantitySample(
                type: HKQuantityType(.leanBodyMass),
                quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: composition.leanMassKg),
                start: date, end: date))
            samples.append(HKQuantitySample(
                type: HKQuantityType(.bodyMassIndex),
                quantity: HKQuantity(unit: .count(), doubleValue: composition.bmi),
                start: date, end: date))
        }

        do {
            try await store.save(samples)
            weighIn.syncedToHealth = true
        } catch {
            // Не блокируем работу приложения из-за «Здоровья».
        }
    }

    /// Все записи о весе, кроме написанных нами же.
    func fetchWeightSamples() async -> [(date: Date, kg: Double)] {
        guard isAvailable else { return [] }
        if !isAuthorized { _ = await requestAuthorization() }
        let ownBundle = Bundle.main.bundleIdentifier

        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: HKQuantityType(.bodyMass),
                                      predicate: nil,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [sort]) { _, samples, _ in
                let result = (samples as? [HKQuantitySample] ?? [])
                    .filter { $0.sourceRevision.source.bundleIdentifier != ownBundle }
                    .map { (date: $0.startDate,
                            kg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo))) }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    /// Что даст импорт, без записи в базу — чтобы показать цифры до подтверждения.
    func previewImport(existing: [WeighIn], skipDuplicates: Bool) async -> ImportResult {
        let samples = await fetchWeightSamples()
        var result = ImportResult(found: samples.count, earliest: samples.first?.date)
        for s in samples {
            if skipDuplicates, Self.isDuplicate(s, in: existing) { result.skipped += 1 }
            else { result.imported += 1 }
        }
        return result
    }

    /// Дубликат — измерение в тот же день с почти тем же весом.
    static func isDuplicate(_ sample: (date: Date, kg: Double), in existing: [WeighIn]) -> Bool {
        let cal = Calendar.current
        return existing.contains { item in
            cal.isDate(item.date, inSameDayAs: sample.date) && abs(item.weightKg - sample.kg) < 0.05
        }
    }
}
