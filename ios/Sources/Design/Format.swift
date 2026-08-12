import Foundation

/// Форматирование как в прототипе: запятая-разделитель, настоящий минус (U+2212),
/// «сегодня / вчера / позавчера» вместо дат.
enum Fmt {
    static let monthsGenitive = ["января", "февраля", "марта", "апреля", "мая", "июня",
                                 "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    static let monthsShort = ["янв", "фев", "мар", "апр", "мая", "июн",
                              "июл", "авг", "сен", "окт", "ноя", "дек"]
    static let weekdaysShort = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]

    /// Число с запятой; nil и NaN превращаются в прочерк.
    static func n(_ v: Double?, _ digits: Int = 2) -> String {
        guard let v, !v.isNaN, !v.isInfinite else { return "—" }
        return String(format: "%.\(digits)f", v).replacingOccurrences(of: ".", with: ",")
    }

    /// Со знаком: «+0,25», «−0,40», «0,00».
    static func signed(_ v: Double, _ digits: Int = 2) -> String {
        let sign = v > 0.0049 ? "+" : v < -0.0049 ? "\u{2212}" : ""
        return sign + n(abs(v), digits)
    }

    static func arrow(_ v: Double) -> String {
        v < -0.0049 ? "↓" : v > 0.0049 ? "↑" : "="
    }

    private static var cal: Calendar { Calendar.current }

    static func dayLabel(_ date: Date, now: Date = Date()) -> String {
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                      to: cal.startOfDay(for: now)).day ?? 0
        switch days {
        case 0: return "сегодня"
        case 1: return "вчера"
        case 2: return "позавчера"
        default:
            let c = cal.dateComponents([.day, .month, .weekday], from: date)
            return "\(c.day ?? 1) \(monthsShort[(c.month ?? 1) - 1]), \(weekdaysShort[(c.weekday ?? 1) - 1])"
        }
    }

    static func time(_ date: Date) -> String {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return "\(c.hour ?? 0):" + String(format: "%02d", c.minute ?? 0)
    }

    /// «пн, 12 августа»
    static func fullDate(_ date: Date) -> String {
        let c = cal.dateComponents([.day, .month, .weekday], from: date)
        return "\(weekdaysShort[(c.weekday ?? 1) - 1]), \(c.day ?? 1) \(monthsGenitive[(c.month ?? 1) - 1])"
    }

    /// «14 сентября» — для даты достижения цели
    static func dayMonth(_ date: Date) -> String {
        let c = cal.dateComponents([.day, .month], from: date)
        return "\(c.day ?? 1) \(monthsGenitive[(c.month ?? 1) - 1])"
    }

    static func shortDayMonth(_ date: Date) -> String {
        let c = cal.dateComponents([.day, .month], from: date)
        return "\(c.day ?? 1) \(monthsShort[(c.month ?? 1) - 1])"
    }
}
