import SwiftUI

/// Первый запуск: весы, профиль, цель. Те же три шага, что в макете,
/// но списки не декоративные — их можно править прямо здесь.
struct OnboardingView: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings

    let sheetHeight: CGFloat
    let onFinish: () -> Void

    @State private var step = 0
    @State private var editingProfile = false
    @State private var searchingScale = false

    var body: some View {
        @Bindable var s = settings

        VStack(alignment: .leading, spacing: 0) {
            Text(L("STEP %d OF 3", step + 1))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.blue)
                .padding(.bottom, 14)

            Text(title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(palette.fg)
            Text(bodyText)
                .font(.body)
                .lineSpacing(3)
                .foregroundStyle(palette.fg2)
                .padding(.top, 12)

            if step == 1 { profileCard.padding(.top, 24) }
            if step == 2 { goalCard.padding(.top, 24) }

            Spacer()

            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i == step ? palette.blue : palette.fg3)
                        .frame(width: 7, height: 7)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 22)

            ActionButton(title: buttonTitle) {
                switch step {
                case 0: searchingScale = true
                case 1: step = 2
                default: finish()
                }
            }

            Button(L("Skip")) { finish() }
                .font(.system(size: 15))
                .foregroundStyle(palette.fg2)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 104)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(palette.bg)
        // Отступы 104 и 34 в макете отсчитываются от краёв экрана, а не от безопасной зоны.
        .ignoresSafeArea()
        .animation(.smooth, value: step)
        .sheet(isPresented: $editingProfile) {
            ProfileEditorView().environment(settings)
        }
        .sheet(isPresented: $searchingScale, onDismiss: { if step == 0 { step = 1 } }) {
            ConnectSheet()
                .presentationDetents([.height(sheetHeight)])
                .presentationCornerRadius(22)
        }
    }

    private func finish() {
        settings.onboardingDone = true
        Task {
            await Reminders.reschedule(enabled: settings.remindersEnabled,
                                       time: settings.reminderTime, lastWeighIn: nil)
        }
        onFinish()
    }

    private var title: String {
        switch step {
        case 0: return L("Let's find your scale")
        case 1: return L("A few numbers about you")
        default: return L("Goal and reminder")
        }
    }

    private var bodyText: String {
        switch step {
        case 0: return L("Step on the scale and stay near your phone. The app will remember it and connect on its own next time.")
        case 1: return L("Height, date of birth and sex are needed to calculate body fat from impedance.")
        default: return L("The goal shows up as a line on the chart, and a push arrives at the chosen time if you haven't weighed in that day.")
        }
    }

    private var buttonTitle: String {
        switch step {
        case 0: return L("Search for scale")
        case 1: return L("Next")
        default: return L("Start")
        }
    }

    private var profileCard: some View {
        Button { editingProfile = true } label: {
            VStack(spacing: 0) {
                onbRow(L("Height"), L("%d cm", Int(settings.profile.heightCm)))
                RowSeparator()
                onbRow(L("Date of birth"), settings.profile.birthDate.formatted(.dateTime.day().month().year()))
                RowSeparator()
                onbRow(L("Sex"), settings.profile.isMale ? L("Male") : L("Female"))
            }
            .card(radius: 20)
        }
        .buttonStyle(.plain)
    }

    private var goalCard: some View {
        @Bindable var s = settings
        return VStack(spacing: 0) {
            Row(title: L("Goal weight"), minHeight: 48) {
                HStack(spacing: 12) {
                    Text(L("%@ kg", Fmt.n(settings.goalWeight, 1)))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(palette.fg2)
                    // Системный шаговик вместо самодельных «−» и «+»:
                    // те же 0,5 кг, но с автоповтором и озвучкой VoiceOver.
                    Stepper(L("Goal weight"), value: $s.goalWeight, in: 40...200, step: 0.5)
                        .labelsHidden()
                }
            }
            RowSeparator()
            Row(title: L("Reminder"), minHeight: 48) {
                Toggle("", isOn: $s.remindersEnabled)
                    .labelsHidden()
                    .accessibilityLabel(L("Reminder"))
                    .tint(palette.green)
            }
            RowSeparator()
            Row(title: L("Save to Health"), minHeight: 48) {
                Toggle("", isOn: $s.healthEnabled)
                    .labelsHidden()
                    .accessibilityLabel(L("Save to Health"))
                    .tint(palette.green)
            }
        }
        .card(radius: 20)
    }

    private func onbRow(_ label: String, _ value: String) -> some View {
        Row(title: label, minHeight: 48) {
            HStack(spacing: 8) {
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(palette.fg2)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
