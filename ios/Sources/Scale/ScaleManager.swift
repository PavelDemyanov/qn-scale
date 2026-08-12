import Foundation
import CoreBluetooth
import Observation

/// Ищет весы по Bluetooth, ведёт обмен по протоколу QN и отдаёт вес наружу.
///
/// Тонкость этой модели: в рекламе она объявляет сервис FFE0, а работает через FFF0 —
/// поэтому ищем по одному UUID, а характеристики берём из другого.
@Observable
@MainActor
final class ScaleManager: NSObject {

    enum State: Equatable {
        case bluetoothOff
        case unauthorized
        case searching
        case connecting
        case negotiating
        case measuring
        case finished

        var caption: String {
            switch self {
            case .bluetoothOff: return "Bluetooth выключен"
            case .unauthorized: return "Нет доступа к Bluetooth"
            case .searching:    return "Встаньте на весы"
            case .connecting:   return "Соединяюсь…"
            case .negotiating:  return "Здороваюсь с весами…"
            case .measuring:    return "Считываю вес…"
            case .finished:     return "Готово"
            }
        }
    }

    private(set) var state: State = .searching
    /// Текущее (ещё «плавающее») значение веса.
    private(set) var liveWeightKg: Double?
    /// Зафиксированное измерение — то, что стоит сохранять.
    private(set) var lastReading: QNProtocol.Reading?
    private(set) var scaleMAC: String?

    /// Вызывается один раз на каждое стабильное измерение.
    var onStableReading: ((QNProtocol.Reading) -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var protocolVersion = QNProtocol.defaultProtocolVersion
    private var publishedThisSession = false
    private var historyTimer: Timer?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Управление

    func startSearching() {
        guard central.state == .poweredOn else { return }
        publishedThisSession = false
        liveWeightKg = nil
        state = .searching
        central.scanForPeripherals(withServices: [CBUUID(string: QNProtocol.advertisedServiceUUID)])
    }

    func stop() {
        central.stopScan()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        historyTimer?.invalidate()
    }

    // MARK: - Обмен

    private func send(_ data: Data, _ why: String) {
        guard let peripheral, let characteristic = writeCharacteristic else { return }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        log("→ \(data.hexString)  (\(why))")
    }

    private func handle(_ packet: QNProtocol.Packet) {
        switch packet {
        case let .hello(mac, version):
            scaleMAC = mac
            protocolVersion = version
            state = .negotiating
            send(QNProtocol.configureKilograms(protocolVersion: version), "единицы = кг")
            send(QNProtocol.setTime(), "текущее время")

        case .configurationAccepted:
            send(QNProtocol.timeSync(protocolVersion: protocolVersion), "синхронизация времени")
            state = .measuring
            scheduleHistoryQuery()

        case let .reading(reading), let .storedReading(reading):
            liveWeightKg = reading.weightKg
            guard reading.isStable, !publishedThisSession else { return }
            publishedThisSession = true
            historyTimer?.invalidate()
            lastReading = reading
            state = .finished
            onStableReading?(reading)

        case .other:
            break
        }
    }

    /// Если живого веса нет — через несколько секунд спросим сохранённое измерение.
    private func scheduleHistoryQuery() {
        historyTimer?.invalidate()
        historyTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.publishedThisSession else { return }
                self.send(QNProtocol.historyQuery(protocolVersion: self.protocolVersion), "запрос истории")
            }
        }
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[Весы] \(message)")
        #endif
    }
}

// MARK: - CBCentralManagerDelegate

extension ScaleManager: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:     startSearching()
            case .unauthorized:  state = .unauthorized
            default:             state = .bluetoothOff
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        Task { @MainActor in
            guard self.peripheral == nil else { return }
            // Имя появляется не в каждом пакете рекламы, поэтому пускаем и безымянные:
            // фильтр по сервису FFE0 уже отсекает всё лишнее.
            guard name.isEmpty || name == QNProtocol.deviceName else { return }
            self.log("нашёл весы: \(name.isEmpty ? "без имени" : name), rssi \(RSSI)")
            self.peripheral = peripheral
            peripheral.delegate = self
            self.state = .connecting
            central.stopScan()
            central.connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.state = .negotiating
            peripheral.discoverServices([CBUUID(string: QNProtocol.gattServiceUUID)])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            self.log("весы отключились")
            self.peripheral = nil
            self.writeCharacteristic = nil
            // Весы засыпают после взвешивания — ждём следующего пробуждения.
            self.startSearching()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension ScaleManager: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            for service in peripheral.services ?? [] {
                peripheral.discoverCharacteristics(
                    [CBUUID(string: QNProtocol.notifyCharacteristicUUID),
                     CBUUID(string: QNProtocol.writeCharacteristicUUID)],
                    for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        Task { @MainActor in
            for characteristic in service.characteristics ?? [] {
                switch characteristic.uuid.uuidString.uppercased() {
                case QNProtocol.notifyCharacteristicUUID:
                    peripheral.setNotifyValue(true, for: characteristic)
                case QNProtocol.writeCharacteristicUUID:
                    self.writeCharacteristic = characteristic
                default:
                    break
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        guard let data = characteristic.value else { return }
        Task { @MainActor in
            self.log("← \(data.hexString)")
            if let packet = QNProtocol.parse(data) { self.handle(packet) }
        }
    }
}

private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined(separator: " ") }
}
