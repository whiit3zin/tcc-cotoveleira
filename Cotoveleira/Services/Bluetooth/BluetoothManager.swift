import Foundation
import CoreBluetooth

// See GATT.md. All multibyte integers are little endian.
final class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let serviceID = CBUUID(string: "4F1B0001-274C-4F4D-8D63-7A7F0C010001")
    static let stateID = CBUUID(string: "4F1B0002-274C-4F4D-8D63-7A7F0C010001")
    static let commandID = CBUUID(string: "4F1B0003-274C-4F4D-8D63-7A7F0C010001")
    static let batteryID = CBUUID(string: "4F1B0004-274C-4F4D-8D63-7A7F0C010001")
    @Published private(set) var status = "Desconectado"
    @Published private(set) var battery: Int?
    @Published private(set) var latestState: (repetition: Int, set: Int, phase: WorkoutPhase)?
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var command: CBCharacteristic?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func scan() {
        guard central.state == .poweredOn else { status = "Bluetooth indisponível"; return }
        status = "Procurando dispositivo"
        central.scanForPeripherals(withServices: [Self.serviceID])
    }

    func disconnect() {
        central.stopScan()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        status = "Desconectado"; battery = nil
    }

    func send(_ code: UInt8, value: UInt16 = 0) {
        guard let peripheral, let command else { return }
        let data = Data([1, code, UInt8(value & 255), UInt8(value >> 8)])
        peripheral.writeValue(data, for: command, type: .withResponse)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn { status = "Bluetooth indisponível"; battery = nil }
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
        battery = nil; command = nil; self.peripheral = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if error != nil { status = "Erro de conexão"; return }
        for service in peripheral.services ?? [] where service.uuid == Self.serviceID {
            peripheral.discoverCharacteristics([Self.stateID, Self.commandID, Self.batteryID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if error != nil { status = "Erro de conexão"; return }
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.stateID: peripheral.setNotifyValue(true, for: characteristic); peripheral.readValue(for: characteristic)
            case Self.commandID: command = characteristic
            case Self.batteryID: peripheral.readValue(for: characteristic); peripheral.setNotifyValue(true, for: characteristic)
            default: break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let bytes = characteristic.value else { return }
        if characteristic.uuid == Self.batteryID {
            if bytes.count == 1, bytes[0] <= 100 { battery = Int(bytes[0]) }
        } else if characteristic.uuid == Self.stateID {
            guard bytes.count == 6, bytes[0] == 1, let phase = WorkoutPhase(rawValue: bytes[1]), bytes[4] > 0 else { return }
            latestState = (Int(bytes[2]) | (Int(bytes[3]) << 8), Int(bytes[4]), phase)
        }
    }
}
