import SwiftUI
import UIKit

/// История: график с масштабированием щипком, итоги за период и список измерений.
struct HistoryView: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings

    let items: [WeighIn]
    let onOpenDay: (WeighIn) -> Void

    @State private var windowDays: Double = 30
    @State private var endDate: Date?
    /// Метку храним датой, а не объектом: при зуме она остаётся привязанной ко времени.
    @State private var markedDate: Date?
    /// Палец держит метку — пока держит, её можно двигать.
    @State private var markerHeld = false
    @State private var touchX: CGFloat = 0
    @State private var gestureBaseWindow: Double?
    @State private var gestureBaseEnd: Date?
    @State private var holdTask: Task<Void, Never>?

    private let chartHeight: CGFloat = 240
    private let axisWidth: CGFloat = 40

    private var stats: Stats { Stats(items: items, goal: settings.goalWeight) }
    private var effectiveEnd: Date { endDate ?? items.last?.date ?? Date() }

    private var visible: [WeighIn] {
        let start = effectiveEnd.addingTimeInterval(-windowDays * 86_400)
        return items.filter { $0.date >= start && $0.date <= effectiveEnd }
    }

    /// «Всё» — ровно длина истории, а не условные десять лет.
    private var allDays: Double {
        guard let first = items.first?.date, let last = items.last?.date else { return 30 }
        return max(7, last.timeIntervalSince(first) / 86_400 + 1)
    }

    private var marked: WeighIn? {
        guard let markedDate else { return nil }
        return items.min { abs($0.date.timeIntervalSince(markedDate)) < abs($1.date.timeIntervalSince(markedDate)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            LargeTitle(text: "История")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            if items.isEmpty {
                emptyState
            } else {
                Segmented(items: [(7.0, "7 дней"), (30.0, "30 дней"), (90.0, "90 дней"), (allDays, "Всё")],
                          selection: Binding(get: { windowDays },
                                             set: { value in
                                                 withAnimation(.smooth(duration: 0.45)) {
                                                     windowDays = value
                                                     endDate = nil
                                                 }
                                             }))
                    .cardInset()
                    .padding(.bottom, 14)

                chartCard
                summarySection
                measurementsSection
            }
        }
        .padding(.top, 58)
        .padding(.bottom, TabBar.reservedHeight + 24)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 100)
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(palette.fg3)
            Text("Пока пусто")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.fg)
            Text("Встаньте на весы — первое измерение появится здесь.")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.fg2)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - График

    private var chartCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("диапазон · \(Int(windowDays.rounded())) дн.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.fg2)
                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Text(spanLabel)
                            .font(.system(size: 24, weight: .semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(palette.fg)
                        Text("кг")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.fg2)
                    }
                }
                Spacer()
                Text("задержите палец — метка\nщипок — масштаб")
                    .font(.system(size: 10))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(palette.fg3)
                    .padding(.top, 3)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)

            GeometryReader { proxy in
                chartBody(width: proxy.size.width)
            }
            .frame(height: chartHeight)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .card()
        .cardInset()
    }

    private var spanLabel: String {
        let ws = visible.map(\.weightKg)
        guard let lo = ws.min(), let hi = ws.max() else { return "—" }
        return "\(Fmt.n(lo, 1)) – \(Fmt.n(hi, 1))"
    }

    private func geometry(width: CGFloat) -> ChartGeometry {
        ChartGeometry.build(items: items, goal: settings.goalWeight, windowDays: windowDays,
                            endDate: effectiveEnd,
                            size: CGSize(width: width, height: chartHeight),
                            padding: .init(top: 14, bottom: 28, leading: 2, trailing: axisWidth),
                            forecastDays: settings.showForecast ? windowDays * 0.3 : 0,
                            slope: stats.slope)
    }

    private func chartBody(width: CGFloat) -> some View {
        let geo = geometry(width: width)
        let markPoint = marked.map { CGPoint(x: geo.x($0.date), y: geo.y($0.weightKg)) }

        return ZStack(alignment: .topLeading) {
            // Засечки идут первыми — иначе серые волоски ложатся поверх кривой.
            ForEach(0..<4, id: \.self) { i in
                let y = geo.y(geo.lo + (geo.hi - geo.lo) * (Double(i) / 3))
                Rectangle()
                    .fill(palette.sep)
                    .frame(width: width - axisWidth, height: 0.5)
                    .position(x: (width - axisWidth) / 2, y: y)
            }

            WeightChart(items: items, goal: settings.goalWeight, slope: stats.slope,
                        size: CGSize(width: width, height: chartHeight),
                        padding: .init(top: 14, bottom: 28, leading: 2, trailing: axisWidth),
                        windowDays: windowDays, endDate: effectiveEnd,
                        forecastFraction: 0.3,
                        showGoalLine: settings.showGoalLine,
                        showForecast: settings.showForecast,
                        showDots: windowDays <= 45)

            axisLabels(geo: geo, width: width)

            if let markPoint, let marked {
                marker(at: markPoint)
                tooltip(for: marked)
                    .offset(x: min(max(0, markPoint.x - 50), max(0, width - axisWidth - 116)), y: 2)
            }
        }
        .animation(.smooth(duration: 0.45), value: windowDays)
        .animation(.smooth(duration: 0.25), value: markedDate)
        .contentShape(Rectangle())
        .gesture(dragGesture(width: width, geo: geo))
        .simultaneousGesture(zoomGesture)
    }

    private func marker(at point: CGPoint) -> some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: point.x, y: 8))
                p.addLine(to: CGPoint(x: point.x, y: chartHeight - 28))
            }
            .stroke(palette.fg3, lineWidth: 1)
            Circle()
                .fill(palette.blue)
                .overlay(Circle().stroke(palette.card, lineWidth: 2.5))
                .frame(width: markerHeld ? 14 : 10, height: markerHeld ? 14 : 10)
                .position(point)
        }
        .animation(.snappy(duration: 0.15), value: markerHeld)
    }

    private func axisLabels(geo: ChartGeometry, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Подписи по оси весов — в полосе справа от поля графика
            ForEach(0..<4, id: \.self) { i in
                let w = geo.lo + (geo.hi - geo.lo) * (Double(i) / 3)
                Text(Fmt.n(w, 1))
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(palette.fg3)
                    .frame(width: axisWidth - 2, alignment: .trailing)
                    .position(x: width - axisWidth / 2, y: geo.y(w))
            }

            if settings.showGoalLine, geo.goalInRange {
                Text(Fmt.n(settings.goalWeight, 1))
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.green)
                    .frame(width: axisWidth - 2, alignment: .trailing)
                    .position(x: width - axisWidth / 2, y: geo.goalY)
            }

            // Подписи дат: центр зажимаем так, чтобы текст не вылезал за плашку
            ForEach(0..<3, id: \.self) { i in
                let t = geo.t0.addingTimeInterval(geo.t1.timeIntervalSince(geo.t0) * Double(i) / 2)
                let half: CGFloat = 27
                Text(Fmt.shortDayMonth(t))
                    .font(.system(size: 10.5))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(palette.fg3)
                    .position(x: min(max(half, geo.x(t)), width - axisWidth - half + 20),
                              y: chartHeight - 8)
            }
        }
    }

    private func tooltip(for item: WeighIn) -> some View {
        let d = delta(for: item)
        return VStack(alignment: .leading, spacing: 1) {
            Text(Fmt.dayLabel(item.date) + ", " + Fmt.time(item.date))
                .font(.system(size: 11))
                .foregroundStyle(palette.fg2)
            Text("\(Fmt.n(item.weightKg)) кг")
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.fg)
            Text(d.map { "\(Fmt.signed($0)) кг" } ?? "первое")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(d.map { palette.delta($0) } ?? palette.fg3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(palette.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 7, y: 4)
    }

    // MARK: - Жесты

    private func mark(atX x: CGFloat, geo: ChartGeometry) {
        if let hit = geo.nearest(toX: x, maxDistance: .greatestFiniteMagnitude) {
            markedDate = hit.item.date
        }
    }

    /// Один жест на всё: пока палец стоит на месте — отсчитываем удержание и
    /// включаем метку, поехал раньше — это панорамирование. Раздельные жесты
    /// (LongPress + Drag) здесь не годятся: включение метки перестраивает вью,
    /// и текущая протяжка обрывается, метка перестаёт ехать за пальцем.
    private func dragGesture(width: CGFloat, geo: ChartGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                touchX = value.location.x

                if holdTask == nil, !markerHeld {
                    let startX = value.startLocation.x
                    holdTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(550))
                        guard !Task.isCancelled else { return }
                        markerHeld = true
                        mark(atX: startX, geo: geo)
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                }

                if markerHeld {
                    mark(atX: value.location.x, geo: geo)
                    return
                }

                guard abs(value.translation.width) > 6 else { return }
                // Палец поехал — это уже сдвиг графика, метку не ставим
                holdTask?.cancel()
                guard let first = items.first?.date, let last = items.last?.date else { return }
                let base = gestureBaseEnd ?? effectiveEnd
                if gestureBaseEnd == nil { gestureBaseEnd = base }
                let shift = Double(value.translation.width / max(width, 1)) * windowDays * 86_400
                let lowerBound = first.addingTimeInterval(windowDays * 86_400 * 0.4)
                endDate = min(last, max(lowerBound, base.addingTimeInterval(-shift)))
            }
            .onEnded { value in
                holdTask?.cancel()
                holdTask = nil
                // Короткий тап без удержания — снять метку
                if !markerHeld, abs(value.translation.width) < 6, abs(value.translation.height) < 6 {
                    markedDate = nil
                }
                markerHeld = false
                gestureBaseEnd = nil
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = gestureBaseWindow ?? windowDays
                if gestureBaseWindow == nil { gestureBaseWindow = base }
                windowDays = min(max(7, allDays), max(7, base / value.magnification))
                // Держим метку по центру окна, если она поставлена
                if let markedDate, let first = items.first?.date, let last = items.last?.date {
                    let centered = markedDate.addingTimeInterval(windowDays * 86_400 / 2)
                    let lowerBound = first.addingTimeInterval(windowDays * 86_400 * 0.4)
                    endDate = min(last, max(lowerBound, centered))
                }
            }
            .onEnded { _ in gestureBaseWindow = nil }
    }

    // MARK: - Итоги и список

    private var summarySection: some View {
        VStack(spacing: 0) {
            SectionHeader(text: "ИТОГ ЗА ПЕРИОД", top: 18)
            VStack(spacing: 0) {
                let ws = visible.map(\.weightKg)
                let change = (visible.count > 1) ? (visible.last!.weightKg - visible.first!.weightKg) : 0
                summaryRow("Изменение", "\(Fmt.signed(change)) кг", palette.delta(change))
                RowSeparator()
                summaryRow("Минимум", ws.min().map { "\(Fmt.n($0)) кг" } ?? "—", palette.fg2)
                RowSeparator()
                summaryRow("Максимум", ws.max().map { "\(Fmt.n($0)) кг" } ?? "—", palette.fg2)
                RowSeparator()
                summaryRow("Взвешиваний", "\(visible.count)", palette.fg2)
            }
            .card()
            .cardInset()
        }
    }

    private func summaryRow(_ label: String, _ value: String, _ color: Color) -> some View {
        Row(title: label, minHeight: 44) {
            Text(value)
                .font(.system(size: 16, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    private var measurementsSection: some View {
        VStack(spacing: 0) {
            SectionHeader(text: "ИЗМЕРЕНИЯ", top: 18)
            VStack(spacing: 0) {
                let rows = Array(visible.reversed().prefix(18))
                ForEach(rows) { item in
                    Button { onOpenDay(item) } label: {
                        measurementRow(item)
                    }
                    .buttonStyle(.plain)
                    if item.id != rows.last?.id { RowSeparator() }
                }
            }
            .card()
            .cardInset()

            Text(visible.count > 18
                 ? "Показаны последние 18 из \(visible.count) за период"
                 : "\(visible.count) измерений за период")
                .font(.system(size: 12))
                .foregroundStyle(palette.fg3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 36)
                .padding(.top, 8)
        }
    }

    private func measurementRow(_ item: WeighIn) -> some View {
        let d = delta(for: item)
        let fat = item.fatPercent(for: settings.profile)
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Fmt.dayLabel(item.date))
                    .font(.system(size: 16))
                    .foregroundStyle(palette.fg)
                Text(fat.map { "\(Fmt.time(item.date)) · жир \(Fmt.n($0, 1)) %" } ?? Fmt.time(item.date))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.fg3)
            }
            Spacer(minLength: 8)
            Text(Fmt.n(item.weightKg))
                .font(.system(size: 17, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(palette.fg)
                .padding(.trailing, 14)
            Text(d.map { Fmt.signed($0) } ?? "—")
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(d.map { palette.delta($0) } ?? palette.fg3)
                .frame(minWidth: 58, alignment: .trailing)
            Chevron().padding(.leading, 10)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private func delta(for item: WeighIn) -> Double? {
        guard let idx = items.firstIndex(where: { $0.id == item.id }), idx > 0 else { return nil }
        return item.weightKg - items[idx - 1].weightKg
    }
}
