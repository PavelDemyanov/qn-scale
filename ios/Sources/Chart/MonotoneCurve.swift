import CoreGraphics

/// Гладкая кривая через точки, которая НЕ выходит за их пределы.
///
/// Обычное сглаживание (Катмулл–Ром и прочие сплайны) уже стояло и было
/// снято: на зубчатых данных отрезок перелетал вершину и заворачивался
/// петлёй — показывал вес, которого не было. Здесь касательные считаются по
/// Стеффену (1990): между двумя соседними точками кривая монотонна, значит
/// не может ни подняться выше верхней из них, ни опуститься ниже нижней, а в
/// вершинах и впадинах касательная горизонтальна. Экстремумы остаются ровно
/// в измерениях, углы уходят.
///
/// Только CoreGraphics — без SwiftUI, чтобы ядро графика могло это
/// проверить обычным swiftc (см. scripts/chart-tests).
enum MonotoneCurve {

    /// Один кубический сегмент Безье: начало — конец предыдущего.
    struct Segment: Equatable {
        let control1: CGPoint
        let control2: CGPoint
        let end: CGPoint
    }

    /// Сегменты через `points` в порядке следования; `x` обязан расти.
    static func segments(_ points: [CGPoint]) -> [Segment] {
        let n = points.count
        guard n >= 2 else { return [] }

        // Шаги и наклоны хорд.
        var h = [CGFloat](repeating: 0, count: n - 1)
        var d = [CGFloat](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            h[i] = Swift.max(points[i + 1].x - points[i].x, 1e-6)
            d[i] = (points[i + 1].y - points[i].y) / h[i]
        }

        // Касательные. На концах — наклон единственной хорды. Внутри: если
        // хорды смотрят в разные стороны, это вершина или впадина — касательная
        // ноль; иначе взвешенное среднее, зажатое так, чтобы по модулю не
        // превышать ни одну из хорд, — отсюда и монотонность.
        var m = [CGFloat](repeating: 0, count: n)
        m[0] = d[0]
        m[n - 1] = d[n - 2]
        if n > 2 {
            for i in 1..<(n - 1) {
                guard d[i - 1] * d[i] > 0 else { m[i] = 0; continue }
                let weighted = (d[i - 1] * h[i] + d[i] * h[i - 1]) / (h[i - 1] + h[i])
                let sign: CGFloat = d[i] > 0 ? 1 : -1
                m[i] = sign * Swift.min(abs(d[i - 1]), abs(d[i]), 0.5 * abs(weighted))
            }
        }

        // Эрмитова кубика → Безье: контрольные точки на трети шага вдоль
        // касательной.
        var out: [Segment] = []
        out.reserveCapacity(n - 1)
        for i in 0..<(n - 1) {
            let third = h[i] / 3
            out.append(Segment(
                control1: CGPoint(x: points[i].x + third, y: points[i].y + m[i] * third),
                control2: CGPoint(x: points[i + 1].x - third, y: points[i + 1].y - m[i + 1] * third),
                end: points[i + 1]))
        }
        return out
    }

    /// Точка сегмента при параметре `t` ∈ 0…1 — для проверок.
    static func point(from start: CGPoint, _ s: Segment, t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, e = t * t * t
        return CGPoint(x: a * start.x + b * s.control1.x + c * s.control2.x + e * s.end.x,
                       y: a * start.y + b * s.control1.y + c * s.control2.y + e * s.end.y)
    }
}
