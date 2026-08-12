import Foundation

/// Язык интерфейса. При первом запуске берётся из языка телефона,
/// дальше переключается в настройках.
enum AppLanguage: String, CaseIterable, Identifiable {
    case ru
    case en

    var id: String { rawValue }

    /// Название языка — всегда на самом языке: так его находят, не зная
    /// текущего.
    var title: String {
        switch self {
        case .ru: return "Русский"
        case .en: return "English"
        }
    }

    /// Флаг страны языка. Не заменяет название, а стоит рядом: флаг —
    /// про страну, а не про язык, и одним им подписывать переключатель нельзя.
    var flag: String {
        switch self {
        case .ru: return "🇷🇺"
        case .en: return "🇺🇸"
        }
    }

    /// Язык по коду системной локали: русский телефон — русский интерфейс,
    /// любой другой — английский. Отрезание двух символов покрывает и «ru»,
    /// и «ru-RU», и «ru-Cyrl-RU».
    static func forSystemCode(_ code: String?) -> AppLanguage {
        code?.prefix(2).lowercased() == "ru" ? .ru : .en
    }

    /// Язык телефона. `Bundle.preferredLocalizations` здесь НЕ годится: у
    /// бандла своя раскладка локализаций, и он вернул бы язык бандла, а не
    /// телефона.
    static var system: AppLanguage { forSystemCode(Locale.preferredLanguages.first) }
}

/// Текущий язык и производная от него локаль.
enum L10n {
    /// Выставляется `AppSettings` при старте и при переключении в настройках.
    static var current: AppLanguage = .ru

    /// Локаль для дат и чисел. Форматтеры обязаны применять её В МОМЕНТ
    /// форматирования, а не при создании: иначе смена языка на лету их не
    /// обновит, и в английском интерфейсе останутся русские месяцы.
    static var locale: Locale {
        Locale(identifier: current == .ru ? "ru_RU" : "en_US")
    }
}

/// Перевод строки интерфейса.
///
/// Ключ — АНГЛИЙСКИЙ текст: он же и показывается в английском интерфейсе,
/// поэтому забытый перевод виден как английская строка, а не как пустое место
/// или технический идентификатор. Так же сделано в соседнем проекте EUC Logger.
func L(_ key: String) -> String {
    L10n.current == .ru ? (russianTranslations[key] ?? key) : key
}

/// Перевод форматной строки с подстановкой (%d, %@, %.1f…). Локаль передаётся
/// явно — иначе дробное число подставится с чужим разделителем.
/// Литеральный процент внутри такой строки экранируется как `%%`.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: L10n.locale, arguments: args)
}

/// Русские формы существительного при числе: 1 запись, 2 записи, 5 записей.
/// Ключ — английское единственное число, то есть то же слово, что стоит в коде.
private let russianPlurals: [String: (one: String, few: String, many: String)] = [
    "record": ("запись", "записи", "записей"),
    "measurement": ("измерение", "измерения", "измерений"),
    "weigh-in": ("взвешивание", "взвешивания", "взвешиваний"),
    "day": ("день", "дня", "дней"),
    "year": ("год", "года", "лет"),
]

/// Число со словом в нужной форме: «3 measurements», «3 измерения».
///
/// Плоская таблица переводов склонять не умеет, и это было видно в интерфейсе:
/// «Найдено 1 записей о весе», «41 лет», «22 измерений». Английское
/// множественное — простое `+s`, и для этих пяти слов оно верное.
func Ln(_ n: Int, _ singular: String) -> String {
    guard L10n.current == .ru, let f = russianPlurals[singular] else {
        return "\(n) " + (n == 1 ? singular : singular + "s")
    }
    let a = abs(n) % 100, b = a % 10
    // 11…14 — исключение: «одиннадцать записей», а не «записи».
    let word = (a > 10 && a < 20) ? f.many
             : b == 1 ? f.one
             : (b >= 2 && b <= 4) ? f.few : f.many
    return "\(n) \(word)"
}
