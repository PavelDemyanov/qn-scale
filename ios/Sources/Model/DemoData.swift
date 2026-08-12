#if DEBUG
import Foundation
import SwiftData

/// Правдоподобная история для проверки вёрстки в симуляторе, где Bluetooth нет.
/// Включается аргументом запуска `-seedDemo`; в релизной сборке кода нет вовсе.
enum DemoData {

    static var isRequested: Bool { CommandLine.arguments.contains("-seedDemo") }

    /// Тот же генератор, что в прототипе: 126 дней, минус 0.52 кг в неделю,
    /// плато на четвёртой-пятой неделе и пропуски дней.
    static func seed(into context: ModelContext) {
        var state: UInt32 = 1337
        func rnd() -> Double {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Double(state) / 4_294_967_296
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let total = 126

        for i in stride(from: total - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            var w = 90.4 - Double(total - 1 - i) * (0.52 / 7)
            if i > 34 && i < 52 { w += 0.6 }
            w += (rnd() - 0.5) * 0.9
            let measured = i == 0 || rnd() < 0.76
            let hour = 7 + Int(rnd() * 2)
            let minute = Int(rnd() * 58)
            guard measured else { continue }
            guard let stamp = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { continue }
            let weight = i == 0 ? 81.10 : (w * 20).rounded() / 20
            let impedance = i == 0 ? 468 : Int((452 + (rnd() - 0.5) * 46).rounded())
            context.insert(WeighIn(date: stamp, weightKg: weight,
                                   impedance1: impedance, impedance2: impedance + 14))
        }
        try? context.save()
    }
}
#endif
