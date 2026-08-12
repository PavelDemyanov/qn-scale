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

    init(date: Date = Date(), weightKg: Double, impedance1: Int, impedance2: Int) {
        self.date = date
        self.weightKg = weightKg
        self.impedance1 = impedance1
        self.impedance2 = impedance2
    }

    func composition(for profile: Profile) -> BodyComposition? {
        BodyComposition.compute(weightKg: weightKg, impedanceOhm: impedance1, profile: profile)
    }
}

/// Профиль живёт в UserDefaults — он маленький и нужен до открытия базы.
@Observable
final class ProfileStore {
    var profile: Profile {
        didSet { save() }
    }

    private static let key = "profile"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(Profile.self, from: data) {
            profile = decoded
        } else {
            profile = Profile()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
