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
    /// Процент жира, пришедший ГОТОВЫМ из «Здоровья». Нужен восстановлению
    /// после переустановки: импеданса в «Здоровье» нет, а сам процент есть —
    /// в том числе записанный нами же до переустановки.
    var healthFatPercent: Double?
    /// Запись из примера истории. Пример нужен человеку, у которого весов ещё
    /// нет: без него приложение выглядит пустым и понять, что оно умеет,
    /// нельзя. Помечаем явно — чтобы пример был виден как пример и удалялся
    /// одним действием, а не притворялся настоящими измерениями.
    var isSample: Bool = false

    init(date: Date = Date(), weightKg: Double, impedance1: Int, impedance2: Int,
         fromHealth: Bool = false, isSample: Bool = false, healthFatPercent: Double? = nil) {
        self.date = date
        self.weightKg = weightKg
        self.impedance1 = impedance1
        self.impedance2 = impedance2
        self.fromHealth = fromHealth
        self.isSample = isSample
        self.healthFatPercent = healthFatPercent
    }

    func composition(for profile: Profile) -> BodyComposition? {
        BodyComposition.compute(weightKg: weightKg, impedanceOhm: impedance1, profile: profile)
    }

    /// Процент жира — единственная метрика состава тела, которую показывает
    /// интерфейс. У записей с весов он считается по импедансу; у пришедших из
    /// «Здоровья» импеданса нет, зато может быть готовое значение.
    func fatPercent(for profile: Profile) -> Double? {
        if let value = composition(for: profile)?.fatPercent, !value.isNaN { return value }
        return healthFatPercent
    }
}
