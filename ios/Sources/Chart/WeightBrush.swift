import SwiftUI

/// Полоса-щётка под графиком: одновременно указатель выбранного окна и главный
/// способ его двигать. Порт щётки из EUC Logger.
struct WeightBrush: View {
    @Environment(\.palette) private var palette
    let model: WeightChartModel
    var height: CGFloat = 44        // цель пальца по HIG; величина ФИЗИЧЕСКАЯ
    var corner: CGFloat = 10

    /// Признак «жест идёт» — в `@GestureState`: нулевой порог щётке НУЖЕН (тап
    /// по полосе переносит окно), и цена этому — лёгкая отменяемость внутри
    /// списка. SwiftUI откатывает `@GestureState` и при ОТМЕНЕ, а `.onEnded`
    /// при отмене не приходит вовсе.
    @GestureState private var brushing = false

    var body: some View {
        GeometryReader { geo in
            let w = Double(geo.size.width)
            Canvas { ctx, size in draw(&ctx, size: size) }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .updating($brushing) { _, s, _ in s = true }
                    .onChanged { v in
                        let f = clamp01(Double(v.location.x) / Swift.max(w, 1))
                        // Захват продолжаем ТОЛЬКО пока жест жив: протухший
                        // захват иначе переживёт конец жеста и молча уведёт
                        // край окна на следующем касании. На первом событии
                        // `brushing` ещё false — это и есть «жест начался».
                        if brushing, model.brushGrab != nil {
                            model.dragBrush(to: f)
                        } else {
                            model.beginBrush(at: f, width: w)   // ширина В ПУНКТАХ
                        }
                    }
                    .onEnded { _ in model.endBrush() })
        }
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(palette.card2.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
            .stroke(palette.sep, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        // Единственная точка выхода из отменённого жеста.
        .onChange(of: brushing) { _, active in
            if !active { model.endBrush() }
        }
        // У Canvas своей доступности нет вовсе, а щётка — главный орган
        // управления этого экрана.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Chart window"))
        .accessibilityValue(model.windowLabel)
        .accessibilityHint(L("Drag the handles to change the range"))
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let w = Double(size.width), h = Double(size.height)
        guard w > 2, h > 6 else { return }
        let s = model.snapshot

        // 1. Мини-превью ВСЕЙ истории. Его может не быть (одно измерение), а
        //    бегунок с ручками обязан нарисоваться всё равно: за него берутся.
        if s.overview.count > 1 {
            var run: [CGPoint] = []
            func flush() {
                defer { run.removeAll(keepingCapacity: true) }
                guard run.count > 1 else { return }
                var p = Path()
                p.addLines(run)
                ctx.stroke(p, with: .color(palette.fg3),
                           style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            }
            for (i, pt) in s.overview.enumerated() {
                // Рвётся по тому же правилу, что большой график: перерыв в
                // истории обязан быть виден и в щётке — по ней и ищут, куда
                // смотреть.
                if i < s.overviewBreaks.count, s.overviewBreaks[i] { flush() }
                run.append(CGPoint(x: pt.x * w, y: h - 4 - pt.y * (h - 8)))
            }
            flush()
        }

        // 2–3. Бегунок берётся ТОЙ ЖЕ структурой, по которой считается
        //      попадание пальца: две арифметики разъехались бы на первой правке.
        let l = BrushLayout(window: model.window, width: w)
        let accent = palette.blue
        ctx.fill(Path(CGRect(x: 0, y: 0, width: Swift.max(0, l.lo), height: h)),
                 with: .color(palette.bg.opacity(0.7)))
        ctx.fill(Path(CGRect(x: l.hi, y: 0, width: Swift.max(0, w - l.hi), height: h)),
                 with: .color(palette.bg.opacity(0.7)))
        ctx.fill(Path(CGRect(x: l.lo, y: 0,
                             width: Swift.max(0, l.hi - l.lo), height: h)),
                 with: .color(accent.opacity(0.16)))

        // 4. Раздутый до пола бегунок про ширину окна ВРЁТ — значит настоящее
        //    окно обязано быть видно внутри него. Заметность метки РАСТЁТ
        //    ВМЕСТЕ С ВРАНЬЁМ, а не включается порогом: порог читается как
        //    поломка («полоска меняет цвет, когда ползунки сближаются»).
        if l.widened {
            let thumb = l.hi - l.lo
            let tw = Swift.max(1.5, l.trueHi - l.trueLo)
            let lie = thumb > 0 ? Swift.min(Swift.max(1 - tw / thumb, 0), 1) : 0
            ctx.fill(Path(CGRect(x: l.trueLo, y: 0, width: tw, height: h)),
                     with: .color(accent.opacity(0.55 * lie)))
        }

        // Центры капсул берём У ГЕОМЕТРИИ: своим зажимом рисование увело бы
        // ручку из её же зоны захвата.
        handle(&ctx, at: l.capLo, h: h, color: accent)
        handle(&ctx, at: l.capHi, h: h, color: accent)
    }

    /// Ручка — КАПСУЛА с насечкой, а не линия в 2 pt: за линию не «хватаются»,
    /// она не читается как орган управления. Обводка и насечка идут цветом
    /// поверхности: приглушённый текстовый на голубой капсуле в светлой теме
    /// исчезает.
    private func handle(_ ctx: inout GraphicsContext, at cx: Double,
                        h: Double, color: Color) {
        let hw = BrushLayout.handle
        let rect = CGRect(x: cx - hw / 2, y: 3, width: hw, height: Swift.max(6, h - 6))
        let cap = Path(roundedRect: rect, cornerRadius: hw / 2)
        ctx.fill(cap, with: .color(color))
        ctx.stroke(cap, with: .color(palette.card), lineWidth: 1)
        let gy = Swift.min(7.0, Double(rect.height) / 2 - 2)
        guard gy > 1 else { return }
        var grip = Path()
        for dx in [-2.5, 2.5] {
            grip.move(to: CGPoint(x: cx + dx, y: h / 2 - gy))
            grip.addLine(to: CGPoint(x: cx + dx, y: h / 2 + gy))
        }
        ctx.stroke(grip, with: .color(palette.card),
                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }

    private func clamp01(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return Swift.min(Swift.max(v, 0), 1)
    }
}
