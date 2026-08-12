import SwiftUI

/// Настройки — системный сгруппированный список: секции с заголовками и подписями,
/// родные Toggle, Stepper, DatePicker и NavigationLink вместо самодельных строк.
struct SettingsView: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    @Environment(ScaleManager.self) private var scale
    @Environment(HealthStore.self) private var health

    let items: [WeighIn]
    let onSearchScale: () -> Void
    let onImportHealth: () -> Void
    let onRestartOnboarding: () -> Void

    private var stats: Stats { Stats(items: items, goal: settings.goalWeight) }

    var body: some View {
        @Bindable var s = settings

        List {
            scaleSection
            goalSection
            chartSection
            healthSection
            remindersSection
            profileSection
            appearanceSection

            Section {
                Button("Пройти настройку заново", action: onRestartOnboarding)
                LabeledContent("Версия", value: "1.0 (1)")
            }
        }
        .navigationTitle("Настройки")
    }

    // MARK: - Весы

    private var scaleSection: some View {
        Section {
            LabeledContent {
                HStack(spacing: 6) {
                    Circle()
                        .fill(scale.state == .measuring || scale.state == .finished
                              ? palette.green : palette.fg3)
                        .frame(width: 7, height: 7)
                    Text(stateLabel)
                }
            } label: {
                Text(settings.knownScaleID == nil ? "Весы не выбраны" : "Libra CS20C1")
                Text(subtitle)
            }

            Button("Искать весы", action: onSearchScale)

            if settings.knownScaleID != nil {
                Button("Забыть эти весы", role: .destructive) {
                    scale.forget()
                    settings.knownScaleID = nil
                    settings.knownScaleMAC = nil
                }
            }
        } header: {
            Text("Весы")
        } footer: {
            Text("Весы просыпаются, когда на них наступают, и засыпают через несколько секунд.")
        }
    }

    private var subtitle: String {
        if let mac = settings.knownScaleMAC ?? scale.scaleMAC { return "QN-Scale · \(mac)" }
        return settings.knownScaleID == nil ? "Нажмите «Искать весы»" : "QN-Scale"
    }

    private var stateLabel: String {
        switch scale.state {
        case .measuring, .finished: return "подключены"
        case .connecting, .negotiating: return "соединяюсь"
        case .bluetoothOff: return "bluetooth выкл."
        case .unauthorized: return "нет доступа"
        case .searching: return settings.knownScaleID == nil ? "не выбраны" : "ожидание"
        }
    }

    // MARK: - Цель

    private var goalSection: some View {
        @Bindable var s = settings
        return Section {
            Stepper(value: $s.goalWeight, in: 40...200, step: 0.5) {
                LabeledContent("Желаемый вес",
                               value: settings.goalWeight,
                               format: .number.precision(.fractionLength(1)))
            }
        } header: {
            Text("Цель")
        } footer: {
            Text(goalFooter)
        }
    }

    private var goalFooter: String {
        guard settings.showForecast, stats.goalDate != nil else {
            return "Линия цели появится на графике."
        }
        return "Линия цели появится на графике; от неё считается прогноз — сейчас это \(stats.goalDateLabel)."
    }

    // MARK: - График

    private var chartSection: some View {
        @Bindable var s = settings
        return Section {
            Toggle("Линия цели", isOn: $s.showGoalLine)
            Toggle("Прогноз веса", isOn: $s.showForecast)
        } header: {
            Text("График")
        } footer: {
            Text("Зелёный пунктир — цель, серый — прогноз по текущему темпу. Выключенные линии пропадают на всех графиках, а вместе с прогнозом — и предсказанные цифры.")
        }
    }

    // MARK: - Здоровье

    private var healthSection: some View {
        @Bindable var s = settings
        return Section {
            Toggle("Записывать в «Здоровье»", isOn: $s.healthEnabled)
                .disabled(!health.isAvailable)
            Button(action: onImportHealth) {
                LabeledContent("Загрузить историю из «Здоровья»",
                               value: settings.importedFromHealth > 0
                                      ? "\(settings.importedFromHealth) записей" : "")
            }
        } header: {
            Text("Здоровье")
        } footer: {
            Text("Вес, процент жира и ИМТ попадут в «Здоровье» — их подхватят другие приложения.")
        }
        .onChange(of: settings.healthEnabled) { _, on in
            if on { Task { _ = await health.requestAuthorization() } }
        }
    }

    // MARK: - Напоминания

    private var remindersSection: some View {
        @Bindable var s = settings
        return Section {
            Toggle("Напоминать взвешиваться", isOn: $s.remindersEnabled)
            DatePicker("Время", selection: reminderDate, displayedComponents: .hourAndMinute)
                .disabled(!settings.remindersEnabled)
        } header: {
            Text("Напоминания")
        } footer: {
            Text("Пуш придёт только если в этот день ещё не было измерения.")
        }
        .onChange(of: settings.remindersEnabled) { _, _ in rescheduleReminders() }
        .onChange(of: settings.reminderTime) { _, _ in rescheduleReminders() }
    }

    /// Время напоминания хранится строкой «8:00» — системному пикеру нужна дата.
    private var reminderDate: Binding<Date> {
        Binding {
            let parts = settings.reminderTime.split(separator: ":").compactMap { Int($0) }
            var components = DateComponents()
            components.hour = parts.first ?? 8
            components.minute = parts.count > 1 ? parts[1] : 0
            return Calendar.current.date(from: components) ?? Date()
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            settings.reminderTime = "\(c.hour ?? 8):" + String(format: "%02d", c.minute ?? 0)
        }
    }

    private func rescheduleReminders() {
        let last = items.last?.date
        let enabled = settings.remindersEnabled
        let time = settings.reminderTime
        Task { await Reminders.reschedule(enabled: enabled, time: time, lastWeighIn: last) }
    }

    // MARK: - Профиль

    private var profileSection: some View {
        Section {
            NavigationLink {
                ProfileEditorView()
            } label: {
                LabeledContent("Профиль", value: profileSummary)
            }
        } footer: {
            Text("Рост, возраст и пол нужны для расчёта процента жира по импедансу.")
        }
    }

    private var profileSummary: String {
        let p = settings.profile
        return "\(Int(p.heightCm)) см · \(p.age) лет · \(p.isMale ? "муж." : "жен.")"
    }

    // MARK: - Вид

    private var appearanceSection: some View {
        @Bindable var s = settings
        return Section {
            Picker("Тема", selection: $s.theme) {
                ForEach(AppTheme.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Главный экран", selection: $s.mainLayout) {
                ForEach(MainLayout.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Вид")
        } footer: {
            Text("Три компоновки главного экрана на выбор — сравните их вживую.")
        }
    }
}

/// Профиль — обычная системная форма.
struct ProfileEditorView: View {
    @Environment(AppSettings.self) private var settings
    @FocusState private var focus: Field?

    private enum Field { case height, calibration }

    var body: some View {
        @Bindable var s = settings
        Form {
            Section {
                LabeledContent("Рост") {
                    HStack {
                        TextField("см", value: $s.profile.heightCm, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focus, equals: .height)
                        Text("см").foregroundStyle(.secondary)
                    }
                }
                DatePicker("Дата рождения", selection: $s.profile.birthDate,
                           in: ...Date(), displayedComponents: .date)
                Picker("Пол", selection: $s.profile.isMale) {
                    Text("Мужской").tag(true)
                    Text("Женский").tag(false)
                }
            } header: {
                Text("Тело")
            } footer: {
                Text("Рост, возраст и пол нужны для расчёта процента жира по импедансу.")
            }

            Section {
                LabeledContent("Поправка жира") {
                    HStack {
                        TextField("0", value: $s.profile.fatCalibration, format: .number)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .focused($focus, equals: .calibration)
                        Text("п.п.").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Калибровка")
            } footer: {
                Text("Процент жира — оценка по импедансу, а не измерение. Если есть чему доверять больше (DXA, InBody) — сдвиньте расчёт на нужное число процентных пунктов.")
            }
        }
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") { focus = nil }.fontWeight(.semibold)
            }
        }
    }
}
