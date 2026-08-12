import SwiftUI

/// История: график с масштабированием щипком, итоги за период и список измерений.
struct HistoryView: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings

    let items: [WeighIn]
    let onOpenDay: (WeighIn) -> Void

    @State private var windowDays: Double = 30
    @State private var endDate: Date?
    @State private var selected: WeighIn?
    @State private var gestureBaseWindow: Double?
    @State private var gestureBaseEnd: Date?

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

    var body: some View {
        VStack(spacing: 0) {
            LargeTitle(text: "История")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            if items.isEmpty {
                emptyState
            } else {
                // Сброс сдвига и выделения — только при выборе периода кнопкой.
                // На onChange он бы срабатывал и на каждом шаге щипка, отменяя сдвиг.
                Segmented(items: [(7.0, "7 дней"), (30.0, "30 дней"), (90.0, "90 дней"), (allDays, "Всё")],
                          selection: Binding(get: { windowDays },
                                             set: { windowDays = $0; endDate = nil; selected = nil }))
                    .cardInset()
                    .padding(.bottom, 14)

                chartCard
                summarySection
                measurementsSection
            }
        }
        .padding(.top, 58)
        .padding(.bottom, 110)
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
                            .foregroundStyle(palette.fg)
                        Text("кг")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.fg2)
                    }
                }
                Spacer()
                Text("щипок — масштаб\nперетаскивание — сдвиг")
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
            .frame(height: 240)
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

    private func chartBody(width: CGFloat) -> some View {
        let size = CGSize(width: width, height: 240)
        let geo = ChartGeometry.build(
            items: items, goal: settings.goalWeight, windowDays: windowDays,
            endDate: effectiveEnd, size: size,
            padding: .init(top: 14, bottom: 28, leading: 2, trailing: 40),
            forecastDays: windowDays * 0.3, slope: stats.slope)

        let selPoint = selected.flatMap { s in geo.samples.first { $0.item.id == s.id }?.point }

        return ZStack(alignment: .topLeading) {
            // Засечки идут ПЕРВЫМИ — иначе серые волоски ложатся поверх кривой.
            ForEach(0..<4, id: \.self) { i in
                let y = geo.y(geo.lo + (geo.hi - geo.lo) * (Double(i) / 3))
                Rectangle()
                    .fill(palette.sep)
                    .frame(width: size.width - 40, height: 0.5)
                    .position(x: (size.width - 40) / 2, y: y)
            }

            WeightChart(geometry: geo,
                        showDots: windowDays <= 45,
                        selected: selPoint)

            // Подписи по оси весов — справа от поля графика
            ForEach(0..<4, id: \.self) { i in
                let w = geo.lo + (geo.hi - geo.lo) * (Double(i) / 3)
                Text(Fmt.n(w, 1))
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(palette.fg3)
                    .frame(width: 38, alignment: .trailing)
                    .position(x: size.width - 19, y: geo.y(w))
            }

            if geo.goalInRange {
                Text(Fmt.n(settings.goalWeight, 1))
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.green)
                    .frame(width: 38, alignment: .trailing)
                    .position(x: size.width - 19, y: geo.goalY)
            }

            // Подписи по оси времени
            ForEach(0..<3, id: \.self) { i in
                let t = geo.t0.addingTimeInterval(geo.t1.timeIntervalSince(geo.t0) * Double(i) / 2)
                Text(Fmt.shortDayMonth(t))
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.fg3)
                    .position(x: geo.x(t), y: 232)
            }

            if let selected, let point = selPoint {
                // Смещение, а не .position: тот задаёт центр, и подсказка вылезала
                // за верхний край графика. Левый край — как в макете, с зажимом.
                tooltip(for: selected)
                    .offset(x: min(max(0, point.x - 50), max(0, size.width - 156)), y: 2)
            }
        }
        .contentShape(Rectangle())
        .gesture(dragGesture(width: width))
        .simultaneousGesture(zoomGesture)
        .onTapGesture { location in
            if let hit = geo.nearest(toX: location.x) {
                selected = selected?.id == hit.item.id ? nil : hit.item
            } else {
                selected = nil
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

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard let first = items.first?.date, let last = items.last?.date else { return }
                let base = gestureBaseEnd ?? effectiveEnd
                if gestureBaseEnd == nil { gestureBaseEnd = base }
                let shift = Double(value.translation.width / max(width, 1)) * windowDays * 86_400
                let lowerBound = first.addingTimeInterval(windowDays * 86_400 * 0.4)
                let candidate = base.addingTimeInterval(-shift)
                endDate = min(last, max(lowerBound, candidate))
            }
            .onEnded { _ in gestureBaseEnd = nil }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = gestureBaseWindow ?? windowDays
                if gestureBaseWindow == nil { gestureBaseWindow = base }
                windowDays = min(3650, max(7, base / value.magnification))
                selected = nil
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
