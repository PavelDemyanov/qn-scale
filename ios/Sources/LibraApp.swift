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

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ScaleManager.self) private var scale
    @Environment(HealthStore.self) private var health
    @Environment(\.palette) private var palette
    @Environment(\.modelContext) private var context

    @Query(sort: \WeighIn.date, order: .forward) private var items: [WeighIn]

    @State private var tab: Tab = .weigh
    @State private var sheet: ActiveSheet?
    @State private var showLive = false
    @State private var showOnboarding = false
    @State private var selectedDay: WeighIn?

    private enum ActiveSheet: Identifiable {
        case connect, healthImport
        var id: Int { self == .connect ? 0 : 1 }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            palette.bg.ignoresSafeArea()

            ScrollView {
                switch tab {
                case .weigh:
                    MainView(items: items,
                             onWeigh: { showLive = true },
                             onGoal: { tab = .settings },
                             onOpenHistory: { tab = .history },
                             onOpenDay: { selectedDay = $0 })
                case .history:
                    HistoryView(items: items, onOpenDay: { selectedDay = $0 })
                case .settings:
                    SettingsView(items: items,
                                 onSearchScale: { sheet = .connect },
                                 onImportHealth: { sheet = .healthImport },
                                 onRestartOnboarding: { showOnboarding = true })
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .bottom)
            // Своя прокрутка на вкладку: иначе позиция переносится с предыдущей.
            .id(tab)

            TabBar(selection: $tab)
        }
        .ignoresSafeArea(.keyboard)
        .onAppear(perform: configure)
        .onChange(of: scale.liveWeightKg) { old, new in
            // Встал на весы без нажатия кнопки — показываем взвешивание само.
            if old == nil, new != nil, sheet == nil, !showOnboarding { showLive = true }
        }
        .fullScreenCover(isPresented: $showLive) {
            LiveWeighView(items: items) {
                showLive = false
                scale.startSearching()
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(onSearchScale: { sheet = .connect },
                           onFinish: { showOnboarding = false })
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .connect:
                ConnectSheet()
                    .presentationDetents([.fraction(0.86)])
                    .presentationCornerRadius(22)
            case .healthImport:
                HealthImportSheet(items: items)
                    .presentationDetents([.fraction(0.78)])
                    .presentationCornerRadius(22)
            }
        }
        .sheet(item: $selectedDay) { item in
            DaySheet(item: item, delta: delta(for: item)) { delete(item) }
                .presentationDetents([.fraction(0.55)])
                .presentationCornerRadius(22)
        }
    }

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

    private func delete(_ item: WeighIn) {
        context.delete(item)
        try? context.save()
    }

    private func delta(for item: WeighIn) -> Double? {
        guard let idx = items.firstIndex(where: { $0.id == item.id }), idx > 0 else { return nil }
        return item.weightKg - items[idx - 1].weightKg
    }
}
