import SwiftUI

struct SettingsView: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    @Environment(ScaleManager.self) private var scale
    @Environment(HealthStore.self) private var health

    let items: [WeighIn]
    let onSearchScale: () -> Void
    let onImportHealth: () -> Void
    let onRestartOnboarding: () -> Void

    @State private var timePickerOpen = false
    @State private var editingProfile = false

    private var stats: Stats { Stats(items: items, goal: settings.goalWeight) }

    var body: some View {
        @Bindable var s = settings

        VStack(spacing: 0) {
            LargeTitle(text: "Настройки")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            scaleSection
            goalSection
            healthSection
            remindersSection
            profileSection
            appearanceSection

            VStack(spacing: 0) {
                Button(action: onRestartOnboarding) {
                    Row(title: "Пройти настройку заново", minHeight: 50, titleColor: palette.blue)
                }
                .buttonStyle(.plain)
                RowSeparator()
                Row(title: "Версия", minHeight: 46) {
                    Text("1.0 (1)")
                        .font(.system(size: 15))
                        .foregroundStyle(palette.fg3)
                }
            }
            .card()
            .cardInset()
            .padding(.top, 20)
        }
        .padding(.top, 58)
        .padding(.bottom, 110)
        .sheet(isPresented: $editingProfile) {
            ProfileEditorView()
                .environment(settings)
        }
    }

    // MARK: - Весы

    private var scaleSection: some View {
        VStack(spacing: 0) {
            SectionHeader(text: "ВЕСЫ", top: 0)
            VStack(spacing: 0) {
                Row(title: settings.knownScaleID == nil ? "Весы не выбраны" : "Libra CS20C1",
                    subtitle: subtitle, minHeight: 56) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(scale.state == .finished || scale.state == .measuring ? palette.green
                                  : settings.knownScaleID != nil ? palette.fg3 : palette.fg3)
                            .frame(width: 7, height: 7)
                        Text(stateLabel)
                            .font(.system(size: 14))
                            .foregroundStyle(palette.fg2)
                    }
                }
                RowSeparator()
                Button(action: onSearchScale) {
                    Row(title: "Искать весы", minHeight: 48, titleColor: palette.blue)
                }
                .buttonStyle(.plain)
                if settings.knownScaleID != nil {
                    RowSeparator()
                    Button {
                        scale.forget()
                        settings.knownScaleID = nil
                        settings.knownScaleMAC = nil
                    } label: {
                        Row(title: "Забыть эти весы", minHeight: 48, titleColor: palette.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .card()
            .cardInset()
            SectionFooter(text: "Весы просыпаются, когда на них наступают, и засыпают через несколько секунд.")
        }
    }

    private var subtitle: String {
        if let mac = settings.knownScaleMAC ?? scale.scaleMAC {
            return "QN-Scale · \(mac)"
        }
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
        VStack(spacing: 0) {
            SectionHeader(text: "ЦЕЛЬ")
            Row(title: "Желаемый вес", minHeight: 52) {
                HStack(spacing: 12) {
                    Text("\(Fmt.n(settings.goalWeight, 1)) кг")
                        .font(.system(size: 17, weight: .medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(palette.fg2)
                    HStack(spacing: 0) {
                        stepperButton("−", size: 20) {
                            settings.goalWeight = max(40, settings.goalWeight - 0.5)
                        }
                        Rectangle().fill(palette.sep).frame(width: 0.5, height: 32)
                        stepperButton("+", size: 18) {
                            settings.goalWeight = min(200, settings.goalWeight + 0.5)
                        }
                    }
                    .background(palette.seg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .card()
            .cardInset()
            SectionFooter(text: goalFooter)
        }
    }

    private var goalFooter: String {
        guard stats.goalDate != nil else {
            return "Линия цели появится на графике. Прогноз посчитается, когда наберётся несколько измерений."
        }
        return "Линия цели появится на графике; от неё считается прогноз — сейчас это \(stats.goalDateLabel)."
    }

    private func stepperButton(_ label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: size))
                .foregroundStyle(palette.fg)
                .frame(width: 42, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Здоровье

    private var healthSection: some View {
        @Bindable var s = settings
        return VStack(spacing: 0) {
            SectionHeader(text: "ЗДОРОВЬЕ")
            VStack(spacing: 0) {
                Row(title: "Записывать в «Здоровье»", minHeight: 52) {
                    Toggle("", isOn: $s.healthEnabled)
                        .labelsHidden()
                        .tint(palette.green)
                        .disabled(!health.isAvailable)
                }
                RowSeparator()
                Button(action: onImportHealth) {
                    Row(title: "Загрузить историю из «Здоровья»", minHeight: 50, titleColor: palette.blue) {
                        Text(settings.importedFromHealth > 0 ? "\(settings.importedFromHealth) записей" : "")
                            .font(.system(size: 14))
                            .foregroundStyle(palette.fg3)
                    }
                }
                .buttonStyle(.plain)
            }
            .card()
            .cardInset()
            SectionFooter(text: "Вес, процент жира и ИМТ попадут в «Здоровье» — их подхватят другие приложения.")
        }
        .onChange(of: settings.healthEnabled) { _, on in
            if on { Task { _ = await health.requestAuthorization() } }
        }
    }

    // MARK: - Напоминания

    private var remindersSection: some View {
        @Bindable var s = settings
        return VStack(spacing: 0) {
            SectionHeader(text: "НАПОМИНАНИЯ")
            VStack(spacing: 0) {
                Row(title: "Напоминать взвешиваться", minHeight: 52) {
                    Toggle("", isOn: $s.remindersEnabled)
                        .labelsHidden()
                        .tint(palette.green)
                }
                RowSeparator()
                Button {
                    if settings.remindersEnabled {
                        withAnimation(.snappy(duration: 0.2)) { timePickerOpen.toggle() }
                    }
                } label: {
                    Row(title: "Время", minHeight: 52) {
                        Text(settings.reminderTime)
                            .font(.system(size: 17, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(timePickerOpen ? palette.blue : palette.fg)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(palette.seg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .buttonStyle(.plain)
                .opacity(settings.remindersEnabled ? 1 : 0.4)

                if timePickerOpen && settings.remindersEnabled {
                    FlexibleTimeGrid(times: AppSettings.reminderTimes,
                                     selection: settings.reminderTime) { time in
                        settings.reminderTime = time
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                    .padding(.top, 2)
                }
            }
            .card()
            .cardInset()
            SectionFooter(text: "Пуш придёт только если в этот день ещё не было измерения.")
        }
        .onChange(of: settings.remindersEnabled) { _, _ in rescheduleReminders() }
        .onChange(of: settings.reminderTime) { _, _ in rescheduleReminders() }
    }

    private func rescheduleReminders() {
        let last = items.last?.date
        let enabled = settings.remindersEnabled
        let time = settings.reminderTime
        Task { await Reminders.reschedule(enabled: enabled, time: time, lastWeighIn: last) }
    }

    // MARK: - Профиль

    private var profileSection: some View {
        VStack(spacing: 0) {
            SectionHeader(text: "ПРОФИЛЬ")
            Button { editingProfile = true } label: {
                VStack(spacing: 0) {
                    profileRow("Рост", "\(Int(settings.profile.heightCm)) см")
                    RowSeparator()
                    profileRow("Дата рождения", settings.profile.birthDate.formatted(.dateTime.day().month().year()))
                    RowSeparator()
                    profileRow("Пол", settings.profile.isMale ? "Мужской" : "Женский")
                    RowSeparator()
                    profileRow("Поправка жира", "\(Fmt.signed(settings.profile.fatCalibration, 1)) п.п.")
                }
            }
            .buttonStyle(.plain)
            .card()
            .cardInset()
            SectionFooter(text: "Рост, возраст и пол нужны для расчёта процента жира по импедансу.")
        }
    }

    private func profileRow(_ label: String, _ value: String) -> some View {
        Row(title: label, minHeight: 48) {
            HStack(spacing: 10) {
                Text(value)
                    .font(.system(size: 16))
                    .monospacedDigit()
                    .foregroundStyle(palette.fg2)
                Chevron()
            }
        }
    }

    // MARK: - Вид

    private var appearanceSection: some View {
        @Bindable var s = settings
        return VStack(spacing: 0) {
            SectionHeader(text: "ВИД")
            VStack(alignment: .leading, spacing: 0) {
                Text("Тема")
                    .font(.system(size: 16))
                    .foregroundStyle(palette.fg)
                    .padding(.bottom, 10)
                Segmented(items: AppTheme.allCases.map { ($0, $0.title) },
                          selection: $s.theme, fontSize: 14, selectedBackground: palette.card2)
                    .padding(.bottom, 18)

                Text("Главный экран")
                    .font(.system(size: 16))
                    .foregroundStyle(palette.fg)
                Text("Три компоновки на выбор — сравните их вживую")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.fg3)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                Segmented(items: MainLayout.allCases.map { ($0, $0.title) },
                          selection: $s.mainLayout, fontSize: 14, selectedBackground: palette.card2)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .card()
            .cardInset()
        }
    }
}

/// Чипы времени напоминания.
private struct FlexibleTimeGrid: View {
    @Environment(\.palette) private var palette
    let times: [String]
    let selection: String
    let onSelect: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 68), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(times, id: \.self) { time in
                let on = time == selection
                Text(time)
                    .font(.system(size: 15))
                    .monospacedDigit()
                    .foregroundStyle(on ? .white : palette.fg)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(on ? palette.blue : palette.seg,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(time) }
            }
        }
    }
}

/// Редактор профиля — то, что прячется за строками с шевронами.
struct ProfileEditorView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?

    private enum Field { case height, calibration }

    var body: some View {
        @Bindable var s = settings
        NavigationStack {
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
                    DatePicker("Дата рождения", selection: $s.profile.birthDate, displayedComponents: .date)
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
