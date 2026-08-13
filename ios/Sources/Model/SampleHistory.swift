import Foundation
import SwiftData

/// Пример истории взвешиваний.
///
/// Это ОБЫЧНАЯ функция приложения, а не режим для проверки: кнопка лежит на
/// пустом экране и в настройках, доступна всем и в любой сборке. Причина
/// простая — пока весов нет, приложению нечего показать, и понять, зачем оно,
/// невозможно: график, цель, прогноз и состав тела берутся из ваших же
/// измерений. Пример даёт увидеть всё это до покупки весов и удаляется одним
/// нажатием.
///
/// Раньше эти данные включались аргументом запуска `-seedDemo` и жили под
/// `#if DEBUG`, то есть в App Store не попадали вовсе. Скриншоты витрины были
/// сняты на них, а человек (в том числе проверяющий из Apple) видел пустой
/// экран — расхождение, за которое приложение справедливо отклонили.
enum SampleHistory {

    /// 126 дней правдоподобной истории: снижение примерно на 0,5 кг в неделю,
    /// плато на четвёртой-пятой неделе, пропущенные дни и разброс между
    /// взвешиваниями. Генератор детерминированный — пример у всех одинаковый.
    static func insert(into context: ModelContext) {
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
                                   impedance1: impedance, impedance2: impedance + 14,
                                   isSample: true))
        }
        try? context.save()
    }

    /// Убрать пример. Настоящие взвешивания не трогаются: удаляются только
    /// записи с пометкой.
    static func remove(from context: ModelContext, items: [WeighIn]) {
        for item in items where item.isSample { context.delete(item) }
        try? context.save()
    }
}
