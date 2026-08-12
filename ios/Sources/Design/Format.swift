import Foundation

/// Форматирование. Числа и даты собирает система по локали устройства —
/// своими остаются только правила, которых у неё нет: настоящий минус в дельтах
/// и «сегодня / вчера / позавчера» вместо даты.
enum Fmt {

    /// Число системным форматом: десятичный разделитель приходит из локали,
    /// а не подставляется руками. nil и NaN превращаются в прочерк.
    static func n(_ v: Double?, _ digits: Int = 2) -> String {
        guard let v, !v.isNaN, !v.isInfinite else { return "—" }
        return v.formatted(.number.precision(.fractionLength(digits)).grouping(.never))
    }

    /// Со знаком: «+0,25», «−0,40», «0,00».
    /// Системный `.sign(strategy: .always())` тут не годится: он ставит обычный
    /// дефис вместо типографского минуса (тот одной ширины с плюсом, и колонка
    /// дельт не дёргается) и печатает знак даже у ровного нуля.
    static func signed(_ v: Double, _ digits: Int = 2) -> String {
        let sign = v > 0.0049 ? "+" : v < -0.0049 ? "\u{2212}" : ""
        return sign + n(abs(v), digits)
    }

    static func arrow(_ v: Double) -> String {
        v < -0.0049 ? "↓" : v > 0.0049 ? "↑" : "="
    }

    private static var cal: Calendar { Calendar.current }

    /// «сегодня» / «вчера» / «позавчера», дальше — дата с днём недели.
    static func dayLabel(_ date: Date, now: Date = Date()) -> String {
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                      to: cal.startOfDay(for: now)).day ?? 0
        switch days {
        case 0: return "сегодня"
        case 1: return "вчера"
        case 2: return "позавчера"
        default:
            return date.formatted(.dateTime.day().month(.abbreviated).weekday(.abbreviated))
        }
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// «пн, 12 августа»
    static func fullDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide))
    }

    /// «14 сентября» — для даты достижения цели
    static func dayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide))
    }

    static func shortDayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }
}
