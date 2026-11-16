import Foundation
import CoreBluetooth

// See GATT.md. All multibyte integers are little endian.
final class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let serviceID = CBUUID(string: "4F1B0001-274C-4F4D-8D63-7A7F0C010001")
    static let stateID = CBUUID(string: "4F1B0002-274C-4F4D-8D63-7A7F0C010001")
    static let commandID = CBUUID(string: "4F1B0003-274C-4F4D-8D63-7A7F0C010001")
    static let batteryID = CBUUID(string: "4F1B0004-274C-4F4D-8D63-7A7F0C010001")
    static let powerID = CBUUID(string: "4F1B0005-274C-4F4D-8D63-7A7F0C010001")
    static let eventID = CBUUID(string: "4F1B0006-274C-4F4D-8D63-7A7F0C010001")
    static let diagnosticID = CBUUID(string: "4F1B0007-274C-4F4D-8D63-7A7F0C010001")
    @Published private(set) var powered: Bool?
    @Published private(set) var ready = false
    @Published private(set) var rssi: Int?
    @Published private(set) var samples: [SensorSample] = []
    @Published private(set) var events: [String] = []
    @Published private(set) var diagnostic: [UInt8] = []
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var minimum: Int?
    @Published private(set) var maximum: Int?
    @Published private(set) var frequency: Double?
    @Published private(set) var configuration: [Int] = []
    var demoMode = false
    var wantsDiagnostics = false
    private var sequence: UInt32?
    private var writes: [Data] = []
    private var writing = false
    func clearDiagnostics() { samples = []; events = []; minimum = nil; maximum = nil; frequency = nil }
    func resetExtrema() { minimum = nil; maximum = nil }
    func diagnostics(_ enabled: Bool) { wantsDiagnostics = enabled; send(10, value: enabled ? 1 : 0) }
    func log(_ message: String) {
        events.append("\(Date.now.formatted(date: .omitted, time: .standard)) \(message)")
        if events.count > 200 { events.removeFirst(events.count - 200) }
    }
    @Published private(set) var status = "Desconectado"
    @Published private(set) var battery: Int?
    @Published private(set) var latestState: (repetition: Int, set: Int, phase: WorkoutPhase)?
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var command: CBCharacteristic?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionRestoreIdentifierKey: "br.edu.tcc.cotoveleira.central"])
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first {
            peripheral = restored; restored.delegate = self
            if restored.state == .connected { restored.discoverServices([Self.serviceID]) }
            else { central.connect(restored) }
        }
    }
    private func clearConnection() {
        ready = false; powered = nil; battery = nil; command = nil; latestState = nil
        sequence = nil; writes = []; writing = false; diagnostic = []; lastUpdate = nil; samples = []
    }
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if error == nil { rssi = RSSI.intValue }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        writing = false
        if let error { writes = []; log(error.localizedDescription) }
        drain()
    }
    private func drain() {
        guard !writing, !writes.isEmpty, let peripheral, let command else { return }
        writing = true; peripheral.writeValue(writes.removeFirst(), for: command, type: .withResponse)
    }
    func scan() {
        guard central.state == .poweredOn else { status = "Bluetooth indisponível"; return }
        status = "Procurando dispositivo"
        central.scanForPeripherals(withServices: [Self.serviceID])
    }

    func disconnect() {
        central.stopScan()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        status = "Desconectado"; clearConnection()
    }

    func send(_ code: UInt8, value: UInt16 = 0) {
        guard !demoMode, command != nil, peripheral?.state == .connected else { return }
        writes.append(Data([1, code, UInt8(value & 255), UInt8(value >> 8)])); drain()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn { status = "Bluetooth indisponível"; clearConnection() }
        else if peripheral == nil { status = "Desconectado" }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        central.stopScan(); self.peripheral = peripheral
        status = "Conectando"; central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "Conectado"; peripheral.delegate = self
        peripheral.discoverServices([Self.serviceID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        status = "Erro de conexão"; self.peripheral = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        status = error == nil ? "Desconectado" : "Erro de conexão"
        clearConnection(); self.peripheral = nil
        if error != nil { central.connect(peripheral) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if error != nil { status = "Erro de conexão"; return }
        for service in peripheral.services ?? [] where service.uuid == Self.serviceID {
            peripheral.discoverCharacteristics([Self.stateID, Self.commandID, Self.batteryID, Self.powerID, Self.eventID, Self.diagnosticID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if error != nil { status = "Erro de conexão"; return }
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.stateID: peripheral.setNotifyValue(true, for: characteristic); peripheral.readValue(for: characteristic)
            case Self.commandID: command = characteristic
            case Self.powerID: peripheral.readValue(for: characteristic); peripheral.setNotifyValue(true, for: characteristic)
            case Self.eventID, Self.diagnosticID: peripheral.setNotifyValue(true, for: characteristic)
            case Self.batteryID: peripheral.readValue(for: characteristic); peripheral.setNotifyValue(true, for: characteristic)
            default: break
            }
        }
        ready = command != nil && service.characteristics?.contains(where: { $0.uuid == Self.powerID }) == true
        if ready { send(10, value: wantsDiagnostics ? 1 : 0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let bytes = characteristic.value else { return }
        if characteristic.uuid == Self.powerID {
            if bytes.count == 1, bytes[0] <= 1 { powered = bytes[0] == 1 }
        } else if characteristic.uuid == Self.eventID {
            guard bytes.count == 7, bytes[0] == 1, (1...4).contains(bytes[1]) else { return }
            let n = UInt32(bytes[3]) | UInt32(bytes[4]) << 8 | UInt32(bytes[5]) << 16 | UInt32(bytes[6]) << 24
            if let sequence, Int32(bitPattern: n &- sequence) <= 0 { return }
            sequence = n
            log("Evento \(bytes[1]); motivo \(bytes[2]); sequência \(n)")
            guard !demoMode else { return }
            let pattern: HapticService.Pattern = bytes[1] == 1 ? .error : bytes[1] == 2 ? .series : bytes[1] == 3 ? .rest : .success
            Task { @MainActor in HapticService.shared.play(pattern) }
        } else if characteristic.uuid == Self.diagnosticID {
            guard bytes.count == 18, bytes[0] == 1 else { return }
            let now = Date.now
            if let lastUpdate { frequency = 1 / max(0.001, now.timeIntervalSince(lastUpdate)) }
            lastUpdate = now; diagnostic = Array(bytes)
            let raw = Int(bytes[1]) | Int(bytes[2]) << 8
            let filtered = Int(bytes[3]) | Int(bytes[4]) << 8
            minimum = min(minimum ?? raw, raw); maximum = max(maximum ?? raw, raw)
            samples.append(SensorSample(date: now, raw: raw, filtered: filtered))
            if samples.count > 300 { samples.removeFirst(samples.count - 300) }
            peripheral.readRSSI()
        } else if characteristic.uuid == Self.batteryID {
            if bytes.count == 1, bytes[0] <= 100 { battery = Int(bytes[0]) }
        } else if characteristic.uuid == Self.stateID {
            guard (bytes.count == 6 || bytes.count == 12), bytes[0] == 1, let phase = WorkoutPhase(rawValue: bytes[1]), bytes[4] > 0 else { return }
            if bytes.count == 12 {
                let rest = Int(bytes[8]) | Int(bytes[9]) << 8
                guard (1...10).contains(bytes[6]), (1...100).contains(bytes[7]), (5...300).contains(rest), bytes[4] <= bytes[6] else { return }
                configuration = [Int(bytes[6]), Int(bytes[7]), rest, Int(bytes[10]) | Int(bytes[11]) << 8, Int(bytes[5])]
            }
            latestState = (Int(bytes[2]) | (Int(bytes[3]) << 8), Int(bytes[4]), phase)
        }
    }
}

struct SensorSample: Identifiable {
    let id = UUID()
    let date: Date
    let raw: Int
    let filtered: Int
}
