import Foundation

/// Уравнение, по которому считается процент жира. Оба выведены для весов
/// «нога–нога», но на разных людях, и на высоком росте расходятся на восемь
/// процентных пунктов — поэтому выбор отдан владельцу, а не зашит намертво.
enum FatFormula: String, Codable, CaseIterable, Identifiable {
    /// Jebb et al., Br J Nutr 2000: 104 мужчины и 101 женщина, рост 1,58–1,93 м,
    /// эталон — четырёхкомпонентная модель, остаточное СКО 4,8 п.п. у мужчин.
    case jebb
    /// Wu et al., Nutr J 2015: тайваньская выборка со средним ростом мужчин
    /// 173 см. Роста отдельным членом в уравнении нет, поэтому на 185–190 см
    /// оно недосчитывает тощую массу и завышает жир.
    case wu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jebb: return L("Jebb (2000)")
        case .wu: return L("Wu (2015)")
        }
    }
}

/// Профиль человека — нужен, чтобы из веса и импеданса посчитать состав тела.
struct Profile: Equatable {
    var heightCm: Double = 178
    var birthDate: Date = Calendar.current.date(byAdding: .year, value: -35, to: Date()) ?? Date()
    var isMale: Bool = true
    /// Поправка к проценту жира в процентных пунктах — если есть чему доверять больше
    /// (DXA, InBody) или хочется сойтись с родным приложением.
    var fatCalibration: Double = 0
    /// Какое уравнение считает жир.
    var fatFormula: FatFormula = .jebb

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
        fatFormula = try c.decodeIfPresent(FatFormula.self, forKey: .fatFormula) ?? fallback.fatFormula
    }
}

/// Состав тела по биоимпедансу.
///
/// Процент жира считается уравнением Jebb et al., British Journal of Nutrition
/// 2000;83:115–122 — оно выведено на весах Tanita с подошвенными электродами,
/// то есть на ТОЙ ЖЕ геометрии «нога–нога», что у наших весов, и проверено по
/// четырёхкомпонентной модели (самый строгий эталон состава тела).
/// Выборка: 104 мужчины и 101 женщина, 16–78 лет, рост 1,58–1,93 м, ИМТ 16–41;
/// остаточное СКО 4,8 процентного пункта у мужчин и 3,3 у женщин.
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

        // ЕДИНИЦЫ: рост в МЕТРАХ. В самой статье под формулой написано «height
        // is in cm», но это опечатка — с сантиметрами получается −390 % жира.
        // С метрами уравнение воспроизводит среднего мужчину их же когорты
        // (1,77 м, 81 кг, 43,8 года, 500 Ом → 23,4 % при ИМТ 25,9), и рост в
        // таблице характеристик выборки там тоже в метрах.
        //
        // Прежде здесь стояло уравнение Wu 2015 (Nutr J 14:52) — тоже
        // «нога–нога», но выведенное на тайваньской выборке со средним ростом
        // 173 см и другим измерительным трактом. На росте 187 см оно давало
        // тощую массу 57 кг, то есть FFMI 16,2 при пороге истощения по ESPEN
        // 17,0, — и это у тренирующегося человека с ИМТ 23. Jebb на тех же
        // измерениях даёт 19–20 % жира и FFMI 18,3, что правдоподобно.
        let rawFatPercent: Double
        switch profile.fatFormula {
        case .jebb:
            rawFatPercent = -156.1
                - 89.1 * log(heightM)
                + 45.6 * log(weightKg)
                + 0.120 * age
                + 0.0494 * Double(impedanceOhm)
                + (profile.isMale ? 0 : 19.6 * log(heightM))
        case .wu:
            // Через тощую массу: уравнение предсказывает именно её.
            let resistanceIndex = (profile.heightCm * profile.heightCm) / Double(impedanceOhm)
            let predictedLean = 13.055
                + 0.204 * weightKg
                + 0.394 * resistanceIndex
                - 0.136 * age
                + 8.125 * sex
            rawFatPercent = (weightKg - predictedLean) / weightKg * 100
        }
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
