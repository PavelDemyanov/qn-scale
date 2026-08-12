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
            languageSection
            scaleSection
            goalSection
            chartSection
            healthSection
            remindersSection
            profileSection
            appearanceSection

            Section {
                Button(L("Run setup again"), action: onRestartOnboarding)
                LabeledContent(L("Version"), value: "1.0 (1)")
            }
        }
        .navigationTitle(L("Settings"))
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
                Text(settings.knownScaleID == nil ? L("No scale selected") : "Libra CS20C1")
                Text(subtitle)
            }

            Button(L("Search for scale"), action: onSearchScale)

            if settings.knownScaleID != nil {
                Button(L("Forget this scale"), role: .destructive) {
                    scale.forget()
                    settings.knownScaleID = nil
                    settings.knownScaleMAC = nil
                }
            }
        } header: {
            Text(L("Scale"))
        } footer: {
            Text(L("The scale wakes up when you step on it and falls asleep a few seconds later."))
        }
    }

    private var subtitle: String {
        if let mac = settings.knownScaleMAC ?? scale.scaleMAC { return "QN-Scale · \(mac)" }
        return settings.knownScaleID == nil ? L("Tap “Search for scale”") : "QN-Scale"
    }

    private var stateLabel: String {
        switch scale.state {
        case .measuring, .finished: return L("connected")
        case .connecting, .negotiating: return L("connecting")
        case .bluetoothOff: return L("Bluetooth off")
        case .unauthorized: return L("no access")
        case .searching: return settings.knownScaleID == nil ? L("not selected") : L("waiting")
        }
    }

    // MARK: - Цель

    private var goalSection: some View {
        @Bindable var s = settings
        return Section {
            Stepper(value: $s.goalWeight, in: 40...200, step: 0.5) {
                LabeledContent(L("Goal weight"),
                               value: settings.goalWeight,
                               format: .number.precision(.fractionLength(1)))
            }
        } header: {
            Text(L("Goal"))
        } footer: {
            Text(goalFooter)
        }
    }

    private var goalFooter: String {
        guard settings.showForecast, stats.goalDate != nil else {
            return L("The goal line will appear on the chart.")
        }
        return L("The goal line will appear on the chart; the forecast is counted from it — right now that is %@.", stats.goalDateLabel)
    }

    // MARK: - График

    private var chartSection: some View {
        @Bindable var s = settings
        return Section {
            Toggle(L("Goal line"), isOn: $s.showGoalLine)
            Toggle(L("Weight forecast"), isOn: $s.showForecast)
        } header: {
            Text(L("Chart"))
        } footer: {
            Text(L("The green dashed line is the goal, the grey one is the forecast at the current rate. Lines you turn off disappear from every chart, and turning off the forecast also hides the predicted numbers."))
        }
    }

    // MARK: - Здоровье

    private var healthSection: some View {
        @Bindable var s = settings
        return Section {
            Toggle(L("Save to Health"), isOn: $s.healthEnabled)
                .disabled(!health.isAvailable)
            Button(action: onImportHealth) {
                LabeledContent(L("Import history from Health"),
                               value: settings.importedFromHealth > 0
                                      ? Ln(settings.importedFromHealth, "record") : "")
            }
        } header: {
            Text(L("Health"))
        } footer: {
            Text(L("Weight, body fat and BMI go to Health — other apps will pick them up."))
        }
        .onChange(of: settings.healthEnabled) { _, on in
            if on { Task { _ = await health.requestAuthorization() } }
        }
    }

    // MARK: - Напоминания

    private var remindersSection: some View {
        @Bindable var s = settings
        return Section {
            Toggle(L("Remind me to weigh in"), isOn: $s.remindersEnabled)
            DatePicker(L("Time"), selection: reminderDate, displayedComponents: .hourAndMinute)
                .disabled(!settings.remindersEnabled)
        } header: {
            Text(L("Reminders"))
        } footer: {
            Text(L("The reminder only arrives if you haven't weighed in that day."))
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
                LabeledContent(L("Profile"), value: profileSummary)
            }
        } footer: {
            Text(L("Height, age and sex are needed to calculate body fat from impedance."))
        }
    }

    private var profileSummary: String {
        let p = settings.profile
        return L("%d cm · %@ · %@", Int(p.heightCm), Ln(p.age, "year"), p.isMale ? L("male") : L("female"))
    }

    // MARK: - Вид

    /// Язык — ПЕРВЫМ и отдельной секцией: это не настройка приложения в один
    /// ряд с темой и напоминаниями, а то, на каком языке читается всё
    /// остальное на этом экране.
    private var languageSection: some View {
        @Bindable var s = settings
        return Section {
            Picker(L("Language"), selection: $s.language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text("\(lang.flag) \(lang.title)").tag(lang)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var appearanceSection: some View {
        @Bindable var s = settings
        return Section {
            Picker(L("Theme"), selection: $s.theme) {
                ForEach(AppTheme.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker(L("Main screen"), selection: $s.mainLayout) {
                ForEach(MainLayout.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text(L("Appearance"))
        } footer: {
            Text(L("Three main-screen layouts to choose from — compare them live."))
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
                LabeledContent(L("Height")) {
                    HStack {
                        TextField(L("cm"), value: $s.profile.heightCm, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focus, equals: .height)
                        Text(L("cm")).foregroundStyle(.secondary)
                    }
                }
                DatePicker(L("Date of birth"), selection: $s.profile.birthDate,
                           in: ...Date(), displayedComponents: .date)
                Picker(L("Sex"), selection: $s.profile.isMale) {
                    Text(L("Male")).tag(true)
                    Text(L("Female")).tag(false)
                }
            } header: {
                Text(L("Body"))
            } footer: {
                Text(L("Height, age and sex are needed to calculate body fat from impedance."))
            }

            Section {
                LabeledContent(L("Body fat offset")) {
                    HStack {
                        TextField("0", value: $s.profile.fatCalibration, format: .number)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .focused($focus, equals: .calibration)
                        Text(L("pp")).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L("Calibration"))
            } footer: {
                Text(L("Body fat is an estimate from impedance, not a measurement. If you have something you trust more (DXA, InBody), shift the calculation by the needed number of percentage points."))
            }
        }
        .navigationTitle(L("Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("Done")) { focus = nil }.fontWeight(.semibold)
            }
        }
    }
}
