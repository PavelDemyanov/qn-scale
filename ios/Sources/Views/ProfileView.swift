import SwiftUI

struct ProfileView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(HealthStore.self) private var health
    @Environment(ScaleManager.self) private var scale
    @FocusState private var isEditingHeight: Bool
    @FocusState private var isEditingFatCalibration: Bool

    var body: some View {
        @Bindable var store = profileStore
        @Bindable var healthStore = health

        NavigationStack {
            Form {
                Section {
                    LabeledContent("Рост") {
                        HStack {
                            TextField("см", value: $store.profile.heightCm, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($isEditingHeight)
                            Text("см").foregroundStyle(.secondary)
                        }
                    }
                    DatePicker("Дата рождения",
                               selection: $store.profile.birthDate,
                               displayedComponents: .date)
                    Picker("Пол", selection: $store.profile.isMale) {
                        Text("Мужской").tag(true)
                        Text("Женский").tag(false)
                    }
                } header: {
                    Text("Тело")
                } footer: {
                    Text("Рост, возраст и пол нужны для расчёта состава тела по импедансу.")
                }

                Section {
                    LabeledContent("Поправка жира") {
                        HStack {
                            TextField("0", value: $store.profile.fatCalibration, format: .number)
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.trailing)
                                .focused($isEditingFatCalibration)
                            Text("п.п.").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Калибровка")
                } footer: {
                    Text("Процент жира у любых бытовых весов — оценка по импедансу, а не измерение. Если есть чему доверять больше (DXA, InBody) — сдвиньте расчёт на нужное число процентных пунктов; отрицательные значения тоже можно.")
                }

                Section {
                    Toggle("Записывать в «Здоровье»", isOn: $healthStore.isEnabled)
                        .disabled(!health.isAvailable)
                    if healthStore.isEnabled && !health.isAuthorized {
                        Button("Разрешить доступ") {
                            Task { await health.requestAuthorization() }
                        }
                    }
                } header: {
                    Text("Здоровье")
                } footer: {
                    Text("Вес, процент жира, тощая масса и ИМТ попадут в «Здоровье» — их подхватят другие приложения.")
                }

                Section {
                    LabeledContent("Состояние", value: scale.state.caption)
                    if let mac = scale.scaleMAC {
                        LabeledContent("Адрес", value: mac)
                    }
                    Button("Искать заново") { scale.startSearching() }
                } header: {
                    Text("Весы")
                } footer: {
                    Text("Весы просыпаются, когда на них наступают, и сами засыпают через несколько секунд.")
                }
            }
            .navigationTitle("Профиль")
            // У цифровой клавиатуры нет своей кнопки скрытия — добавляем.
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") {
                        isEditingHeight = false
                        isEditingFatCalibration = false
                    }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
