import SwiftUI

enum AppTheme: String, CaseIterable {
    case dark, light
    var title: String { self == .dark ? "Тёмная" : "Светлая" }
    var palette: Palette { self == .dark ? .dark : .light }
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
}

/// Три компоновки главного экрана из макета.
enum MainLayout: String, CaseIterable {
    case numbers = "a", chart = "b", goal = "c"
    var title: String {
        switch self {
        case .numbers: return "Числа"
        case .chart: return "График"
        case .goal: return "Цель"
        }
    }
}

/// Всё, что хранится между запусками, кроме самих взвешиваний.
@Observable
final class AppSettings {
    var profile: Profile { didSet { save(profile, "profile") } }
    var goalWeight: Double { didSet { d.set(goalWeight, forKey: "goalWeight") } }
    var theme: AppTheme { didSet { d.set(theme.rawValue, forKey: "theme") } }
    var mainLayout: MainLayout { didSet { d.set(mainLayout.rawValue, forKey: "mainLayout") } }
    var healthEnabled: Bool { didSet { d.set(healthEnabled, forKey: "healthEnabled") } }
    var remindersEnabled: Bool { didSet { d.set(remindersEnabled, forKey: "remindersEnabled") } }
    var reminderTime: String { didSet { d.set(reminderTime, forKey: "reminderTime") } }
    var onboardingDone: Bool { didSet { d.set(onboardingDone, forKey: "onboardingDone") } }
    /// Идентификатор запомненных весов — к ним подключаемся молча.
    var knownScaleID: String? { didSet { d.set(knownScaleID, forKey: "knownScaleID") } }
    var knownScaleMAC: String? { didSet { d.set(knownScaleMAC, forKey: "knownScaleMAC") } }
    var importedFromHealth: Int { didSet { d.set(importedFromHealth, forKey: "importedFromHealth") } }

    static let reminderTimes = ["6:30", "7:00", "7:30", "8:00", "8:30", "9:00", "9:30", "10:00"]

    private let d = UserDefaults.standard

    init() {
        profile = Self.load(Profile.self, "profile") ?? Profile()
        goalWeight = d.object(forKey: "goalWeight") as? Double ?? 78
        theme = AppTheme(rawValue: d.string(forKey: "theme") ?? "") ?? .dark
        mainLayout = MainLayout(rawValue: d.string(forKey: "mainLayout") ?? "") ?? .numbers
        healthEnabled = d.bool(forKey: "healthEnabled")
        remindersEnabled = d.bool(forKey: "remindersEnabled")
        reminderTime = d.string(forKey: "reminderTime") ?? "8:00"
        onboardingDone = d.bool(forKey: "onboardingDone")
        knownScaleID = d.string(forKey: "knownScaleID")
        knownScaleMAC = d.string(forKey: "knownScaleMAC")
        importedFromHealth = d.integer(forKey: "importedFromHealth")
    }

    var palette: Palette { theme.palette }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { d.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
