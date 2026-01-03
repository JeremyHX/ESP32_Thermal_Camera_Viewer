import Foundation
import CoreBluetooth

@Observable
class BLEManager: NSObject {
    // MARK: - Constants
    static let vendorId: UInt16 = 0x09C7
    static let productType: UInt8 = 0x04
    static let serviceUUID = CBUUID(string: "00000100-CAAB-3792-3D44-97AE51C1407A")
    static let characteristicUUID = CBUUID(string: "00000101-CAAB-3792-3D44-97AE51C1407A")

    // MARK: - State
    enum ConnectionState {
        case disconnected
        case scanning
        case connecting
        case connected
    }

    var state: ConnectionState = .disconnected
    var isBluetoothAvailable: Bool = false
    var discoveredDeviceName: String?
    var rssi: Int = 0

    // Temperature data (in Celsius, already converted)
    var aMax: Double = 0
    var bMax: Double = 0
    var cMax: Double = 0
    var dMax: Double = 0
    var aCenter: Double = 0  // Burner temperature used as center
    var bCenter: Double = 0
    var cCenter: Double = 0
    var dCenter: Double = 0

    // Callbacks
    var onTemperaturesUpdated: (() -> Void)?

    // MARK: - Private
    private var centralManager: CBCentralManager!
    private var thermoHoodPeripheral: CBPeripheral?
    private var probeCharacteristic: CBCharacteristic?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public Methods

    func startScanning() {
        guard isBluetoothAvailable else { return }
        state = .scanning
        // Scan for all devices to catch advertising data
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
    }

    func stopScanning() {
        centralManager.stopScan()
        if state == .scanning {
            state = .disconnected
        }
    }

    func disconnect() {
        // Stop scanning first
        centralManager.stopScan()

        // Disconnect from peripheral if connected
        if let peripheral = thermoHoodPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        thermoHoodPeripheral = nil
        probeCharacteristic = nil
        state = .disconnected
        discoveredDeviceName = nil
    }

    // MARK: - Temperature Decoding

    /// Decode 8 temperatures from 13 bytes of packed data (13 bits per temperature)
    private func decodeTemperatures(from data: Data) -> [Double] {
        guard data.count >= 13 else { return [] }

        var temperatures: [Double] = []
        var bitPosition = 0

        for _ in 0..<8 {
            var rawValue: UInt16 = 0

            for bit in 0..<13 {
                let byteIndex = (bitPosition + bit) / 8
                let bitInByte = 7 - ((bitPosition + bit) % 8)

                if byteIndex < data.count && (data[byteIndex] & (1 << bitInByte)) != 0 {
                    rawValue |= (1 << (12 - bit))
                }
            }
            bitPosition += 13

            // Convert to Celsius: (rawValue × 0.05) - 20
            let celsius = (Double(rawValue) * 0.05) - 20.0        }

        return temperatures
    }

    /// Update stored temperatures from decoded array
    private func updateTemperatures(_ temps: [Double]) {
        guard temps.count == 8 else { return }

        aMax = temps[0]
        bMax = temps[1]
        cMax = temps[2]
        dMax = temps[3]
        aCenter = temps[4]  // Burner temps used as "center"
        bCenter = temps[5]
        cCenter = temps[6]
        dCenter = temps[7]

        DispatchQueue.main.async {
            self.onTemperaturesUpdated?()
        }
    }

    /// Process manufacturer data from advertising packet
    private func processAdvertisingData(_ mfrData: Data, rssi: NSNumber) {
        guard mfrData.count >= 24 else { return }

        // Check vendor ID and product type
        let vendorId = UInt16(mfrData[0]) | (UInt16(mfrData[1]) << 8)
        let productType = mfrData[2]

        guard vendorId == Self.vendorId && productType == Self.productType else { return }

        self.rssi = rssi.intValue

        // Extract serial number for device identification
        let serial = UInt32(mfrData[3]) | (UInt32(mfrData[4]) << 8) |
                     (UInt32(mfrData[5]) << 16) | (UInt32(mfrData[6]) << 24)
        discoveredDeviceName = String(format: "ThermoHood-%08X", serial)

        // Decode temperatures from bytes 7-19
        let tempData = mfrData.subdata(in: 7..<20)
        let temps = decodeTemperatures(from: tempData)
        updateTemperatures(temps)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isBluetoothAvailable = central.state == .poweredOn
        if !isBluetoothAvailable {
            state = .disconnected
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {

        guard let mfrData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else {
            return
        }

        processAdvertisingData(mfrData, rssi: RSSI)

        // Update state if we found a device
        if state == .scanning && discoveredDeviceName != nil {
            // Stay in scanning mode but mark as receiving data
            // Optionally connect for GATT notifications
            if thermoHoodPeripheral == nil {
                thermoHoodPeripheral = peripheral
                peripheral.delegate = self
                state = .connecting
                centralManager.connect(peripheral, options: nil)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = .connected
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // Fall back to advertising-only mode
        state = .scanning
        thermoHoodPeripheral = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        thermoHoodPeripheral = nil
        probeCharacteristic = nil

        // If we were connected, try to reconnect
        if state == .connected {
            state = .scanning
            startScanning()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }

        for service in services where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.characteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let characteristics = service.characteristics else { return }

        for char in characteristics where char.uuid == Self.characteristicUUID {
            probeCharacteristic = char
            peripheral.setNotifyValue(true, for: char)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == Self.characteristicUUID,
              let data = characteristic.value else { return }

        // GATT notification contains temperature data directly
        let temps = decodeTemperatures(from: data)
        updateTemperatures(temps)
    }
}
