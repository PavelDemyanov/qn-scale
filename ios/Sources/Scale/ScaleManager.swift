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

        /// Подписи из макета: четыре фазы взвешивания.
        var caption: String {
            switch self {
            case .bluetoothOff: return L("Bluetooth is off")
            case .unauthorized: return L("No Bluetooth access")
            case .searching:    return L("Step on the scale")
            case .connecting, .negotiating: return L("Connecting…")
            case .measuring:    return L("Reading weight…")
            case .finished:     return L("Done")
            }
        }

        var hint: String {
            switch self {
            case .bluetoothOff: return L("Turn on Bluetooth in Control Center")
            case .unauthorized: return L("Allow Bluetooth access in iOS Settings")
            case .searching:    return L("The scale wakes up when you step on it")
            case .connecting, .negotiating: return L("Handshaking with the scale over the QN protocol")
            case .measuring:    return L("Do not step off until the number settles")
            case .finished:     return L("Measurement saved to History")
            }
        }

        var phase: Int {
            switch self {
            case .searching, .bluetoothOff, .unauthorized: return 0
            case .connecting, .negotiating: return 1
            case .measuring: return 2
            case .finished: return 3
            }
        }
    }

    /// Шаги рукопожатия — их показывает шторка поиска весов.
    struct Handshake: Equatable {
        var serviceFound = false
        var unitsConfigured = false
        var timeSynced = false
        var streaming = false

        var allDone: Bool { serviceFound && unitsConfigured && timeSynced && streaming }
    }

    private(set) var state: State = .searching
    private(set) var liveWeightKg: Double?
    private(set) var lastReading: QNProtocol.Reading?
    private(set) var scaleMAC: String?
    private(set) var handshake = Handshake()
    /// Найденные, но ещё не подключённые весы — для шторки поиска.
    private(set) var candidateName: String?
    private(set) var candidateRSSI: Int?

    var onStableReading: ((QNProtocol.Reading) -> Void)?
    /// Идентификатор запомненных весов; к чужим устройствам молча не подключаемся.
    var knownScaleID: String?
    var onScaleRemembered: ((String, String?) -> Void)?

    /// В режиме подбора ждём подтверждения пользователя перед подключением.
    private(set) var pairingMode = false

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var candidate: CBPeripheral?
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
        guard central?.state == .poweredOn else { return }
        publishedThisSession = false
        liveWeightKg = nil
        handshake = Handshake()
        state = .searching
        central.scanForPeripherals(withServices: [CBUUID(string: QNProtocol.advertisedServiceUUID)],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    /// Режим подбора: показываем найденные весы и ждём нажатия «Подключить».
    func startPairing() {
        pairingMode = true
        candidate = nil
        candidateName = nil
        candidateRSSI = nil
        handshake = Handshake()
        disconnect()
        startSearching()
    }

    func confirmPairing() {
        guard let candidate else { return }
        pairingMode = false
        knownScaleID = candidate.identifier.uuidString
        onScaleRemembered?(candidate.identifier.uuidString, scaleMAC)
        connect(to: candidate)
    }

    func cancelPairing() {
        pairingMode = false
        candidate = nil
        candidateName = nil
        startSearching()
    }

    func forget() {
        knownScaleID = nil
        scaleMAC = nil
        disconnect()
        state = .searching
    }

    func stop() {
        central?.stopScan()
        disconnect()
        historyTimer?.invalidate()
    }

    private func disconnect() {
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        writeCharacteristic = nil
    }

    private func connect(to p: CBPeripheral) {
        central.stopScan()
        peripheral = p
        p.delegate = self
        state = .connecting
        central.connect(p)
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
            handshake.serviceFound = true
            state = .negotiating
            send(QNProtocol.configureKilograms(protocolVersion: version), "единицы = кг")
            handshake.unitsConfigured = true
            send(QNProtocol.setTime(), "текущее время")

        case .configurationAccepted:
            send(QNProtocol.timeSync(protocolVersion: protocolVersion), "синхронизация времени")
            handshake.timeSynced = true
            state = .measuring
            scheduleHistoryQuery()

        case let .reading(reading), let .storedReading(reading):
            handshake.streaming = true
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
            // Имя есть не в каждом пакете рекламы, поэтому пускаем и безымянные:
            // фильтр по сервису FFE0 уже отсекает всё лишнее.
            guard name.isEmpty || name == QNProtocol.deviceName else { return }

            if pairingMode {
                guard candidate == nil else { return }
                candidate = peripheral
                candidateName = name.isEmpty ? QNProtocol.deviceName : name
                candidateRSSI = RSSI.intValue
                central.stopScan()
                return
            }

            guard self.peripheral == nil else { return }
            // Если весы уже запомнены — подключаемся только к ним.
            if let known = knownScaleID, peripheral.identifier.uuidString != known { return }
            if knownScaleID == nil {
                knownScaleID = peripheral.identifier.uuidString
                onScaleRemembered?(peripheral.identifier.uuidString, nil)
            }
            connect(to: peripheral)
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
            // Весы засыпают после взвешивания — сразу возвращаемся к прослушиванию
            // эфира, чтобы следующее взвешивание подхватилось само.
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
