import Foundation

/// Профиль человека — нужен, чтобы из веса и импеданса посчитать состав тела.
struct Profile: Equatable {
    var heightCm: Double = 178
    var birthDate: Date = Calendar.current.date(byAdding: .year, value: -35, to: Date()) ?? Date()
    var isMale: Bool = true
    /// Поправка к проценту жира в процентных пунктах — если есть чему доверять больше
    /// (DXA, InBody) или хочется сойтись с родным приложением.
    var fatCalibration: Double = 0

    var age: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 35
    }
}

extension Profile: Codable {
    // Свой разбор, чтобы добавление новых полей не обнуляло уже сохранённый профиль.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Profile()
        heightCm = try c.decodeIfPresent(Double.self, forKey: .heightCm) ?? fallback.heightCm
        birthDate = try c.decodeIfPresent(Date.self, forKey: .birthDate) ?? fallback.birthDate
        isMale = try c.decodeIfPresent(Bool.self, forKey: .isMale) ?? fallback.isMale
        fatCalibration = try c.decodeIfPresent(Double.self, forKey: .fatCalibration) ?? 0
    }
}

/// Состав тела по биоимпедансу.
///
/// Тощая масса считается уравнением, выведенным именно для весов «нога–нога»
/// (Lu et al., Nutrition Journal 2015; 554 человека, сверка по DXA, r² = 0.92,
/// стандартная ошибка 3.17 кг). Уравнения клинических приборов «рука–нога»
/// (Kyle, Sun) для напольных весов не годятся: у них другая геометрия измерения.
///
/// Всё остальное выводится из тощей массы так же, как это делает родное приложение:
/// вода — 73% тощей массы (константа гидратации), кости — 5%, мышцы — остальное,
/// обмен веществ — по Кетчу–Макардлу.
///
/// Абсолютный процент жира у любых бытовых весов — оценка с разбросом в несколько
/// процентных пунктов, и она заметно зависит от обезвоживания и сухости кожи на стопах.
/// Динамика день ко дню куда надёжнее самой цифры.
struct BodyComposition: Equatable {
    var fatPercent: Double
    var fatMassKg: Double
    var leanMassKg: Double
    var muscleMassKg: Double
    var waterPercent: Double
    var boneMassKg: Double
    var bmi: Double
    var basalMetabolismKcal: Double
    /// Оценка жира только по ИМТ, возрасту и полу (Deurenberg 1991) — без импеданса.
    /// Показываем рядом как «средний человек с такими же ростом, весом и возрастом».
    var fatPercentByBMI: Double

    /// Индекс массы тела — единственная величина состава тела, которой не нужен
    /// импеданс: только рост и вес. Поэтому она считается и для записей,
    /// введённых руками или пришедших из «Здоровья».
    static func bmi(weightKg: Double, heightCm: Double) -> Double? {
        let m = heightCm / 100
        guard m > 0.5, weightKg > 0 else { return nil }
        return weightKg / (m * m)
    }

    /// Доля воды в тощей массе — физиологическая константа.
    private static let hydrationOfLeanMass = 0.73
    /// Доля костного минерала в тощей массе.
    private static let boneShareOfLeanMass = 0.05

    static func compute(weightKg: Double, impedanceOhm: Int, profile: Profile) -> BodyComposition? {
        let heightM = profile.heightCm / 100
        guard weightKg > 0, heightM > 0 else { return nil }

        let age = Double(profile.age)
        let sex = profile.isMale ? 1.0 : 0.0
        let bmi = weightKg / (heightM * heightM)
        let fatByBMI = 1.20 * bmi + 0.23 * age - 10.8 * sex - 5.4

        // Импеданс вне разумного диапазона (весы его не измерили — например, в носках):
        // отдаём только то, что считается по росту и весу.
        guard (200...900).contains(impedanceOhm) else {
            return BodyComposition(fatPercent: .nan, fatMassKg: .nan, leanMassKg: .nan,
                                   muscleMassKg: .nan, waterPercent: .nan, boneMassKg: .nan,
                                   bmi: bmi, basalMetabolismKcal: 370 + 21.6 * weightKg * 0.75,
                                   fatPercentByBMI: fatByBMI)
        }

        let resistanceIndex = (profile.heightCm * profile.heightCm) / Double(impedanceOhm)
        let predictedLean = 13.055
            + 0.204 * weightKg
            + 0.394 * resistanceIndex
            - 0.136 * age
            + 8.125 * sex

        // Считаем через процент жира: так поправка пользователя остаётся согласованной
        // со всеми остальными показателями.
        let rawFatPercent = (weightKg - predictedLean) / weightKg * 100
        let fatPercent = min(max(rawFatPercent + profile.fatCalibration, 3), 60)

        let leanMass = weightKg * (1 - fatPercent / 100)
        let bone = leanMass * boneShareOfLeanMass

        return BodyComposition(
            fatPercent: fatPercent,
            fatMassKg: weightKg - leanMass,
            leanMassKg: leanMass,
            muscleMassKg: leanMass - bone,
            waterPercent: leanMass * hydrationOfLeanMass / weightKg * 100,
            boneMassKg: bone,
            bmi: bmi,
            basalMetabolismKcal: 370 + 21.6 * leanMass,   // Кетч–Макардл
            fatPercentByBMI: fatByBMI)
    }
}
