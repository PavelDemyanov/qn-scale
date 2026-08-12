import SwiftUI
import SwiftData

@main
struct LibraApp: App {
    @State private var settings = AppSettings()
    @State private var scale = ScaleManager()
    @State private var health = HealthStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(scale)
                .environment(health)
                .environment(\.palette, settings.palette)
                .preferredColorScheme(settings.theme.colorScheme)
                .tint(settings.palette.blue)
        }
        .modelContainer(for: WeighIn.self)
    }
}

enum Tab: String, CaseIterable {
    case weigh, history, settings

    var title: String {
        switch self {
        case .weigh: return "Вес"
        case .history: return "История"
        case .settings: return "Настройки"
        }
    }

    var symbol: String {
        switch self {
        case .weigh: return "scalemass"
        case .history: return "chart.xyaxis.line"
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ScaleManager.self) private var scale
    @Environment(HealthStore.self) private var health
    @Environment(\.palette) private var palette
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \WeighIn.date, order: .forward) private var items: [WeighIn]

    @State private var tab: Tab = .weigh
    @State private var sheet: ActiveSheet?
    @State private var showLive = false
    @State private var showOnboarding = false
    @State private var showManualEntry = false
    @State private var selectedDay: WeighIn?

    private enum ActiveSheet: Identifiable {
        case connect, healthImport
        var id: Int { self == .connect ? 0 : 1 }
    }

    /// Полная высота экрана — от неё считаются высоты шторок, как в макете
    /// (шторка поиска начинается в 120 пунктах от верха, импорт — в 150, день — в 300).
    @State private var screenHeight: CGFloat = 874

    private func sheetHeight(topInset: CGFloat) -> CGFloat {
        max(320, screenHeight - topInset)
    }

    var body: some View {
        // Панель вкладок — системная: на iOS 26 она сама рисуется «жидким стеклом»
        // и сама отводит место содержимому. Содержимое неактивной вкладки НЕ строится
        // (заглушка обязана быть непустой, иначе SwiftUI убирает кнопку вкладки).
        TabView(selection: $tab) {
            Group { if tab == .weigh { weighTab } else { Color.clear } }
                .tabItem { Label(Tab.weigh.title, systemImage: Tab.weigh.symbol) }
                .tag(Tab.weigh)

            Group { if tab == .history { historyTab } else { Color.clear } }
                .tabItem { Label(Tab.history.title, systemImage: Tab.history.symbol) }
                .tag(Tab.history)

            Group { if tab == .settings { settingsTab } else { Color.clear } }
                .tabItem { Label(Tab.settings.title, systemImage: Tab.settings.symbol) }
                .tag(Tab.settings)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { screenHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, new in screenHeight = new }
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea(.keyboard)
        .onAppear(perform: configure)
        // Пока приложение открыто, оно всё время слушает эфир: наступили на весы —
        // экран взвешивания открывается сам, нажимать ничего не нужно.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { scale.startSearching() } else { scale.stop() }
        }
        .onChange(of: scale.liveWeightKg) { old, new in
            if old == nil, new != nil, sheet == nil, selectedDay == nil,
               !showOnboarding, !showManualEntry {
                showLive = true
            }
        }
        .fullScreenCover(isPresented: $showLive) {
            LiveWeighView(items: items) {
                showLive = false
                scale.startSearching()
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            // Шторку поиска онбординг показывает сам: два модальных экрана с одного
            // контроллера UIKit не показывает, и запрос молча терялся.
            OnboardingView(sheetHeight: sheetHeight(topInset: 120),
                           onFinish: { showOnboarding = false })
        }
        .sheet(isPresented: $showManualEntry) {
            ManualWeightSheet(lastWeight: items.last?.weightKg) { weight, date in
                addManual(weight: weight, date: date)
            }
            .presentationDetents([.height(sheetHeight(topInset: 150))])
            .presentationCornerRadius(22)
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .connect:
                ConnectSheet()
                    .presentationDetents([.height(sheetHeight(topInset: 120))])
                    .presentationCornerRadius(22)
            case .healthImport:
                HealthImportSheet(items: items)
                    .presentationDetents([.height(sheetHeight(topInset: 150))])
                    .presentationCornerRadius(22)
            }
        }
        .sheet(item: $selectedDay) { item in
            DaySheet(item: item, delta: delta(for: item)) { delete(item) }
                .presentationDetents([.height(sheetHeight(topInset: 300))])
                .presentationCornerRadius(22)
        }
    }

    // MARK: - Вкладки

    /// Общая обёртка: фон во весь экран и прокрутка, начинающаяся от физического
    /// верха (в макете все экраны отсчитывают свои 58 пунктов оттуда, а статус-бар
    /// лежит поверх содержимого). Низ безопасной зоны не трогаем — там панель вкладок.
    private func screen<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .top) {
            palette.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    content()
                    Spacer(minLength: 0)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
        }
    }

    private var weighTab: some View {
        screen {
            MainView(items: items,
                     onManualAdd: { showManualEntry = true },
                     onGoal: { tab = .settings },
                     onOpenHistory: { tab = .history },
                     onOpenDay: { selectedDay = $0 })
        }
    }

    private var historyTab: some View {
        screen {
            HistoryView(items: items, onOpenDay: { selectedDay = $0 })
        }
    }

    private var settingsTab: some View {
        screen {
            SettingsView(items: items,
                         onSearchScale: { sheet = .connect },
                         onImportHealth: { sheet = .healthImport },
                         onRestartOnboarding: { showOnboarding = true })
        }
    }

    // MARK: - Данные

    private func configure() {
        #if DEBUG
        if DemoData.isRequested, items.isEmpty {
            DemoData.seed(into: context)
            settings.onboardingDone = true
        }
        #endif
        scale.knownScaleID = settings.knownScaleID
        scale.onScaleRemembered = { id, mac in
            settings.knownScaleID = id
            if let mac { settings.knownScaleMAC = mac }
        }
        scale.onStableReading = { reading in save(reading) }
        if !settings.onboardingDone { showOnboarding = true }
    }

    private func save(_ reading: QNProtocol.Reading) {
        // Весы повторяют финальный кадр — не плодим одинаковые записи.
        if let last = items.last,
           abs(last.weightKg - reading.weightKg) < 0.01,
           Date().timeIntervalSince(last.date) < 120 {
            return
        }
        let weighIn = WeighIn(weightKg: reading.weightKg,
                              impedance1: reading.impedance1,
                              impedance2: reading.impedance2)
        context.insert(weighIn)
        try? context.save()

        Reminders.cancelToday()
        let enabled = settings.healthEnabled
        let profile = settings.profile
        Task { await health.save(weighIn: weighIn, profile: profile, enabled: enabled) }
    }

    private func addManual(weight: Double, date: Date) {
        let weighIn = WeighIn(date: date, weightKg: weight, impedance1: 0, impedance2: 0)
        context.insert(weighIn)
        try? context.save()
        Reminders.cancelToday()
        let enabled = settings.healthEnabled
        let profile = settings.profile
        Task { await health.save(weighIn: weighIn, profile: profile, enabled: enabled) }
    }

    private func delete(_ item: WeighIn) {
        context.delete(item)
        try? context.save()
    }

    private func delta(for item: WeighIn) -> Double? {
        guard let idx = items.firstIndex(where: { $0.id == item.id }), idx > 0 else { return nil }
        return item.weightKg - items[idx - 1].weightKg
    }
}
