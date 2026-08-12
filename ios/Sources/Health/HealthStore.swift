import Foundation
import HealthKit

/// Запись веса и состава тела в «Здоровье».
@Observable
@MainActor
final class HealthStore {

    private let store = HKHealthStore()
    private(set) var isAuthorized = false

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "healthEnabled") }
    }

    private var types: Set<HKQuantityType> {
        Set([HKQuantityType(.bodyMass),
             HKQuantityType(.bodyFatPercentage),
             HKQuantityType(.leanBodyMass),
             HKQuantityType(.bodyMassIndex)])
    }

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: "healthEnabled")
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: types, read: types)
            isAuthorized = true
        } catch {
            isAuthorized = false
        }
    }

    /// Пишет одно взвешивание. Молча ничего не делает, если синхронизация выключена.
    func save(weighIn: WeighIn, profile: Profile) async {
        guard isEnabled, isAvailable else { return }
        if !isAuthorized { await requestAuthorization() }

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
}
