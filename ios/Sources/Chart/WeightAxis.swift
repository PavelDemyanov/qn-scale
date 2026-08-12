import Foundation

/// Шкала весов. Круглые деления — не косметика: пока `lo`/`hi` брались сырыми,
/// все четыре подписи менялись на каждом кадре протяжки.
enum WeightAxis {

    static let steps: [Double] = [0.2, 0.5, 1, 2, 5, 10, 20]

    /// Самый МЕЛКИЙ круглый шаг, при котором засечек не больше `maxTicks`.
    ///
    /// Считать шаг как «размах, делённый на число делений» нельзя: соседние
    /// круглые шаги отличаются вдвое, и размах 16,8 кг попадал на шаг 10 —
    /// шкала растягивалась с 76…92 до 70…100, а кривая садилась на треть
    /// высоты кадра. Перебор от мелкого к крупному берёт первый подходящий,
    /// то есть самую тесную круглую шкалу.
    static func nice(lo: Double, hi: Double,
                     maxTicks: Int = 5) -> (lo: Double, hi: Double, step: Double) {
        let want = Double(Swift.max(2, maxTicks) - 1)
        for step in steps {
            let a = (lo / step).rounded(.down) * step
            let b = (hi / step).rounded(.up) * step
            if (b - a) / step <= want + 1e-9 {
                return (a, b > a ? b : a + step, step)
            }
        }
        let step = steps.last!
        let a = (lo / step).rounded(.down) * step
        var b = (hi / step).rounded(.up) * step
        if b <= a { b = a + step }
        return (a, b, step)
    }

    static func ticks(lo: Double, hi: Double, step: Double) -> [Double] {
        guard step > 0, hi > lo, ((hi - lo) / step) < 100 else { return [lo] }
        return stride(from: lo, through: hi + step / 2, by: step).map { $0 }
    }
}
