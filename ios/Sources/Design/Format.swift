import Foundation

/// Форматирование. Числа и даты собирает система — своими остаются только
/// правила, которых у неё нет: настоящий минус в дельтах и «сегодня / вчера /
/// позавчера» вместо даты.
///
/// Локаль везде передаётся ЯВНО (`L10n.locale`), а не берётся текущая: язык
/// интерфейса переключается внутри приложения, и без этого в английском
/// интерфейсе остались бы русские месяцы, а в русском — точка вместо запятой.
enum Fmt {

    /// Число системным форматом: десятичный разделитель приходит из локали,
    /// а не подставляется руками. nil и NaN превращаются в прочерк.
    static func n(_ v: Double?, _ digits: Int = 2) -> String {
        guard let v, !v.isNaN, !v.isInfinite else { return "—" }
        return v.formatted(.number.precision(.fractionLength(digits))
            .grouping(.never).locale(L10n.locale))
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
        case 0: return L("today")
        case 1: return L("yesterday")
        case 2: return L("2 days ago")
        default:
            return date.formatted(.dateTime.day().month(.abbreviated)
                .weekday(.abbreviated).locale(L10n.locale))
        }
    }

    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened)
            .locale(L10n.locale))
    }

    /// «пн, 12 августа»
    static func fullDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide)
            .locale(L10n.locale))
    }

    /// «14 сентября» — для даты достижения цели
    static func dayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).locale(L10n.locale))
    }

    static func shortDayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(L10n.locale))
    }

    /// Короткое название дня недели для столбиков: «ПН», «MON».
    static func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).locale(L10n.locale))
    }
}
