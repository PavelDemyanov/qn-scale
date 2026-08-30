import Foundation
import HealthKit

/// Запись веса в «Здоровье» и импорт истории оттуда.
@Observable
@MainActor
final class HealthStore {

    /// Одна запись из «Здоровья»: вес, а также импеданс и процент жира, если
    /// они там нашлись.
    struct Sample {
        let date: Date
        let kg: Double
        let fatPercent: Double?
        /// Импеданс, который приложение положило в примечания к своей же
        /// записи. Есть только у записей, сделанных начиная с этой версии.
        let impedanceOhm: Int?
    }

    /// Ключи примечаний. Импеданс кладётся к записи о весе, потому что без него
    /// вернувшаяся из «Здоровья» история перестаёт пересчитываться: остаётся
    /// один замороженный процент жира, посчитанный давно и, возможно, другой
    /// формулой.
    private static let impedanceKey = "com.redpax.Libra.impedance"
    private static let impedance2Key = "com.redpax.Libra.impedance2"

    struct ImportResult {
        var found = 0
        var imported = 0
        var skipped = 0
        var earliest: Date?
    }

    private let store = HKHealthStore()
    private(set) var isAuthorized = false

    private var shareTypes: Set<HKQuantityType> {
        Set([HKQuantityType(.bodyMass),
             HKQuantityType(.bodyFatPercentage),
             HKQuantityType(.leanBodyMass),
             HKQuantityType(.bodyMassIndex)])
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            // Читаем и жир тоже: без него восстановленная история состоит из
            // одних килограммов, хотя проценты в «Здоровье» лежат рядом.
            try await store.requestAuthorization(
                toShare: shareTypes,
                read: [HKQuantityType(.bodyMass), HKQuantityType(.bodyFatPercentage)])
            isAuthorized = true
        } catch {
            isAuthorized = false
        }
        return isAuthorized
    }

    /// Пишет одно взвешивание.
    func save(weighIn: WeighIn, profile: Profile, enabled: Bool) async {
        guard enabled, isAvailable else { return }
        if !isAuthorized { _ = await requestAuthorization() }

        var samples: [HKQuantitySample] = []
        let date = weighIn.date

        var meta: [String: Any] = [:]
        if weighIn.impedance1 > 0 { meta[Self.impedanceKey] = weighIn.impedance1 }
        if weighIn.impedance2 > 0 { meta[Self.impedance2Key] = weighIn.impedance2 }

        samples.append(HKQuantitySample(
            type: HKQuantityType(.bodyMass),
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weighIn.weightKg),
            start: date, end: date,
            metadata: meta.isEmpty ? nil : meta))

        // ИМТ зависит только от роста и веса, поэтому уходит и у записей без
        // импеданса — у ручного ввода и у импорта из «Здоровья». Раньше он
        // лежал под проверкой процента жира и терялся вместе с ним, хотя
        // описание в App Store обещает «вес, жир и ИМТ».
        if let bmi = BodyComposition.bmi(weightKg: weighIn.weightKg, heightCm: profile.heightCm) {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.bodyMassIndex),
                quantity: HKQuantity(unit: .count(), doubleValue: bmi),
                start: date, end: date))
        }

        if let composition = weighIn.composition(for: profile), !composition.fatPercent.isNaN {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.bodyFatPercentage),
                quantity: HKQuantity(unit: .percent(), doubleValue: composition.fatPercent / 100),
                start: date, end: date))
            samples.append(HKQuantitySample(
                type: HKQuantityType(.leanBodyMass),
                quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: composition.leanMassKg),
                start: date, end: date))
        }

        do {
            try await store.save(samples)
            weighIn.syncedToHealth = true
        } catch {
            // Не блокируем работу приложения из-за «Здоровья».
        }
    }

    /// ВСЕ записи о весе из «Здоровья», включая написанные нами же.
    ///
    /// Прежде свои записи отбрасывались по bundle id — при живой базе это
    /// избавляло от дублей. Но именно они и составляют самую свежую часть
    /// истории, и после переустановки «загрузить историю» возвращала всё, кроме
    /// последних недель, то есть кроме того, ради чего её и зовут. Дубли
    /// отсекает проверка по дню и весу, а не по источнику: своя запись, если
    /// она в базе уже есть, отсеется как дубликат сама.
    func fetchWeightSamples() async -> [Sample] {
        guard isAvailable else { return [] }
        if !isAuthorized { _ = await requestAuthorization() }

        async let weights = quantitySamples(HKQuantityType(.bodyMass))
        async let fats = quantitySamples(HKQuantityType(.bodyFatPercentage))

        // Жир кладётся к весу ПО ВРЕМЕНИ: обе величины пишутся одним
        // взвешиванием, но разными записями. Минутная сетка с проверкой соседей
        // прощает расхождение в секунду-другую между ними.
        var fatByMinute: [Int: Double] = [:]
        for f in await fats {
            fatByMinute[Self.minute(f.startDate)] = f.quantity.doubleValue(for: .percent()) * 100
        }
        return await weights.map { w in
            let key = Self.minute(w.startDate)
            let fat = fatByMinute[key] ?? fatByMinute[key - 1] ?? fatByMinute[key + 1]
            return Sample(date: w.startDate,
                          kg: w.quantity.doubleValue(for: .gramUnit(with: .kilo)),
                          fatPercent: fat,
                          impedanceOhm: w.metadata?[Self.impedanceKey] as? Int)
        }
    }

    private static func minute(_ d: Date) -> Int { Int(d.timeIntervalSince1970 / 60) }

    private func quantitySamples(_ type: HKQuantityType) async -> [HKQuantitySample] {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: nil,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            store.execute(query)
        }
    }

    /// Что даст импорт, без записи в базу — чтобы показать цифры до подтверждения.
    func previewImport(existing: [WeighIn], skipDuplicates: Bool) async -> ImportResult {
        let samples = await fetchWeightSamples()
        var result = ImportResult(found: samples.count, earliest: samples.first?.date)
        for s in samples {
            if skipDuplicates, Self.isDuplicate(s, in: existing) { result.skipped += 1 }
            else { result.imported += 1 }
        }
        return result
    }

    /// Дубликат — измерение в тот же день с почти тем же весом.
    static func isDuplicate(_ sample: Sample, in existing: [WeighIn]) -> Bool {
        let cal = Calendar.current
        return existing.contains { item in
            cal.isDate(item.date, inSameDayAs: sample.date) && abs(item.weightKg - sample.kg) < 0.05
        }
    }
}
