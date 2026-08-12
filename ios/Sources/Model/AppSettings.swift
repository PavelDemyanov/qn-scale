import SwiftUI

enum AppTheme: String, CaseIterable {
    case dark, light
    var title: String { self == .dark ? L("Dark") : L("Light") }
    var palette: Palette { self == .dark ? .dark : .light }
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
}

/// Три компоновки главного экрана из макета.
enum MainLayout: String, CaseIterable {
    case numbers = "a", chart = "b", goal = "c"
    var title: String {
        switch self {
        case .numbers: return L("Numbers")
        case .chart: return L("Chart")
        case .goal: return L("Goal")
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
    /// Зелёный пунктир цели на графиках.
    var showGoalLine: Bool { didSet { d.set(showGoalLine, forKey: "showGoalLine") } }
    /// Серый пунктир прогноза и разделы с предсказанным весом.
    var showForecast: Bool { didSet { d.set(showForecast, forKey: "showForecast") } }
    /// Язык интерфейса. Держится ЗДЕСЬ, а не в системных настройках телефона:
    /// переключение внутри приложения меняет язык сразу, без перезапуска.
    var language: AppLanguage {
        didSet {
            d.set(language.rawValue, forKey: "language")
            L10n.current = language
        }
    }

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
        // По умолчанию обе линии включены — но только если пользователь их ещё не трогал.
        showGoalLine = d.object(forKey: "showGoalLine") as? Bool ?? true
        showForecast = d.object(forKey: "showForecast") as? Bool ?? true
        // Первый запуск — берём язык телефона.
        language = AppLanguage(rawValue: d.string(forKey: "language") ?? "") ?? .system
        L10n.current = language
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
