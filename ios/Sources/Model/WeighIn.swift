import Foundation
import SwiftData

/// Одно взвешивание. Храним сырьё (вес и импеданс), а состав тела считаем на лету —
/// так исправление роста или даты рождения пересчитывает всю историю.
@Model
final class WeighIn {
    var date: Date = Date()
    var weightKg: Double = 0
    var impedance1: Int = 0
    var impedance2: Int = 0
    var syncedToHealth: Bool = false
    /// Запись пришла импортом из «Здоровья», а не с весов: импеданса у неё нет.
    var fromHealth: Bool = false

    init(date: Date = Date(), weightKg: Double, impedance1: Int, impedance2: Int, fromHealth: Bool = false) {
        self.date = date
        self.weightKg = weightKg
        self.impedance1 = impedance1
        self.impedance2 = impedance2
        self.fromHealth = fromHealth
    }

    func composition(for profile: Profile) -> BodyComposition? {
        BodyComposition.compute(weightKg: weightKg, impedanceOhm: impedance1, profile: profile)
    }

    /// Процент жира — единственная метрика состава тела, которую показывает интерфейс.
    func fatPercent(for profile: Profile) -> Double? {
        guard let value = composition(for: profile)?.fatPercent, !value.isNaN else { return nil }
        return value
    }
}
