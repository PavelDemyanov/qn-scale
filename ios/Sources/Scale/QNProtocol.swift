import Foundation

/// Протокол весов QN (Qingniu/Yolanda) — то, что удалось снять с Libra CS20C1.
///
/// Кадр: `[опкод][длина][версия протокола][...данные...][сумма]`,
/// где сумма — это сумма всех предыдущих байтов по модулю 256.
///
/// Обмен целиком:
/// ```
/// весы → 0x12  «привет»: MAC, версия протокола
/// мы   → 0x13  единицы измерения (0x01 = кг)
/// мы   → 0x02  текущее время (4 байта LE, эпоха с 2000-01-01) — без контрольной суммы
/// весы → 0x14  «настройки приняты»
/// мы   → 0x20  синхронизация времени
/// весы → 0x10  измерение: вес (байты 3-4, BE, сотые доли кг), стабильность (байт 5),
///              импеданс (байты 6-7 и 8-9, BE)
/// мы   → 0x22  запрос сохранённых измерений, если живых не пришло
/// весы → 0x23  сохранённое измерение: вес (байты 10-11 BE /100), импеданс (13-14, 15-16 LE)
/// ```
enum QNProtocol {

    /// Весы рекламируют этот сервис…
    static let advertisedServiceUUID = "FFE0"
    /// …а в таблице GATT у них на самом деле вот этот.
    static let gattServiceUUID = "FFF0"
    static let notifyCharacteristicUUID = "FFF1"
    static let writeCharacteristicUUID = "FFF2"
    static let deviceName = "QN-Scale"

    /// Весы считают время в секундах от 2000-01-01 (смещение как в openScale).
    static let epochOffset: TimeInterval = 946_702_800

    static let defaultProtocolVersion: UInt8 = 0x15

    // MARK: - Входящие пакеты

    enum Packet {
        /// Весы представились: MAC и версия протокола, которую нужно возвращать в ответах.
        case hello(mac: String, protocolVersion: UInt8)
        /// Настройки приняты — пора синхронизировать время.
        case configurationAccepted
        /// Живое измерение.
        case reading(Reading)
        /// Измерение из памяти весов (ответ на запрос истории).
        case storedReading(Reading)
        /// Что-то, что мы пока не разбираем.
        case other(opcode: UInt8)
    }

    struct Reading: Equatable {
        var weightKg: Double
        var isStable: Bool
        /// Два значения импеданса (Ом) — весы меряют сопротивление двумя парами электродов.
        var impedance1: Int
        var impedance2: Int
    }

    // MARK: - Разбор

    static func parse(_ data: Data) -> Packet? {
        let b = [UInt8](data)
        guard b.count >= 3 else { return nil }

        switch b[0] {
        case 0x12 where b.count > 10:
            let mac = b[3...8].reversed().map { String(format: "%02x", $0) }.joined(separator: ":")
            return .hello(mac: mac, protocolVersion: b[2])

        case 0x14:
            return .configurationAccepted

        case 0x10 where b.count >= 10:
            return .reading(Reading(weightKg: weight(raw: be(b[3], b[4])),
                                    isStable: b[5] == 1,
                                    impedance1: be(b[6], b[7]),
                                    impedance2: be(b[8], b[9])))

        case 0x23 where b.count >= 17:
            return .storedReading(Reading(weightKg: weight(raw: be(b[10], b[11])),
                                          isStable: true,
                                          impedance1: le(b[13], b[14]),
                                          impedance2: le(b[15], b[16])))

        default:
            return .other(opcode: b[0])
        }
    }

    /// Проверка контрольной суммы. Кадр времени (0x02) её не содержит, для остальных сходится.
    static func isChecksumValid(_ data: Data) -> Bool {
        let b = [UInt8](data)
        guard let last = b.last, b.count >= 2 else { return false }
        return checksum(Array(b.dropLast())) == last
    }

    // MARK: - Исходящие команды

    static func configureKilograms(protocolVersion: UInt8) -> Data {
        framed([0x13, 0x09, protocolVersion, 0x01 /* кг */, 0x10, 0x00, 0x00, 0x00])
    }

    /// Кадр времени идёт без контрольной суммы — так делает и родное приложение.
    static func setTime(now: Date = Date()) -> Data {
        Data([0x02] + timeBytes(now: now))
    }

    static func timeSync(protocolVersion: UInt8, now: Date = Date()) -> Data {
        framed([0x20, 0x08, protocolVersion] + timeBytes(now: now))
    }

    static func historyQuery(protocolVersion: UInt8) -> Data {
        framed([0x22, 0x06, protocolVersion, 0x00, 0x03])
    }

    // MARK: - Мелочи

    static func checksum(_ bytes: [UInt8]) -> UInt8 {
        UInt8(bytes.reduce(0) { $0 + Int($1) } & 0xFF)
    }

    static func framed(_ payload: [UInt8]) -> Data {
        Data(payload + [checksum(payload)])
    }

    static func timeBytes(now: Date = Date()) -> [UInt8] {
        let seconds = UInt32(max(0, now.timeIntervalSince1970 - epochOffset))
        return [UInt8(seconds & 0xFF),
                UInt8((seconds >> 8) & 0xFF),
                UInt8((seconds >> 16) & 0xFF),
                UInt8((seconds >> 24) & 0xFF)]
    }

    private static func be(_ hi: UInt8, _ lo: UInt8) -> Int { Int(hi) << 8 | Int(lo) }
    private static func le(_ lo: UInt8, _ hi: UInt8) -> Int { Int(hi) << 8 | Int(lo) }

    /// На CS20C1 вес приходит в сотых долях килограмма. У части ревизий QN — в десятых,
    /// поэтому если результат выходит за границы разумного, пробуем другой делитель.
    private static func weight(raw: Int) -> Double {
        let hundredths = Double(raw) / 100.0
        return (2.0...300.0).contains(hundredths) ? hundredths : Double(raw) / 10.0
    }
}
