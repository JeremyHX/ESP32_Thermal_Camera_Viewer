# Thermohood BLE Protocol

This document describes the Bluetooth Low Energy (BLE) protocol used by the ESP32 thermal camera for broadcasting temperature data. The protocol is compatible with Combustion Inc. probe devices.

## Overview

The thermal camera broadcasts 8 temperature values via BLE:
- 4 quadrant maximum temperatures (hottest pixel in each quadrant)
- 4 burner temperatures (user-configured point in each quadrant)

Temperature data is available in two ways:
1. **Advertising packets** - Passive monitoring without connection
2. **GATT notifications** - Active connection with push updates

## Device Discovery

### Advertising Data

The device advertises with manufacturer-specific data containing real-time temperatures.

**Advertising Interval:** 250ms (normal mode)

**Manufacturer Data Format (24 bytes):**

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0-1 | 2 | Vendor ID | `0xC7 0x09` (little-endian 0x09C7) |
| 2 | 1 | Product Type | `0x04` (Thermohood) |
| 3-6 | 4 | Serial Number | BT MAC bytes 2-5 (little-endian), see [Device Identification](#device-identification) |
| 7-19 | 13 | Temperature Data | 8 temperatures × 13 bits packed |
| 20 | 1 | Mode/ID | `0x00` (normal mode) |
| 21 | 1 | Battery/Virtual | `0xFF` (full battery, no virtual sensors) |
| 22 | 1 | Network Info | `0x00` |
| 23 | 1 | Overheating | `0x00` (no overheating flags) |

### Identifying the Device

To identify a Thermohood device in BLE scan results:

```swift
// Check manufacturer data
if manufacturerData.count >= 3 {
    let vendorId = UInt16(manufacturerData[0]) | (UInt16(manufacturerData[1]) << 8)
    let productType = manufacturerData[2]

    if vendorId == 0x09C7 && productType == 0x04 {
        // This is a Thermohood device
    }
}
```

---

## Temperature Encoding

### Bit Packing

8 temperature values are packed into 13 bytes using 13 bits per temperature (104 bits total).

**Bit Layout:**
```
Byte  0: T1[12:5]
Byte  1: T1[4:0] | T2[12:10]
Byte  2: T2[9:2]
Byte  3: T2[1:0] | T3[12:7]
Byte  4: T3[6:0] | T4[12]
Byte  5: T4[11:4]
Byte  6: T4[3:0] | T5[12:9]
Byte  7: T5[8:1]
Byte  8: T5[0] | T6[12:6]
Byte  9: T6[5:0] | T7[12:11]
Byte 10: T7[10:3]
Byte 11: T7[2:0] | T8[12:8]
Byte 12: T8[7:0]
```

### Temperature Mapping

| Index | Register | Quadrant | Description |
|-------|----------|----------|-------------|
| T1 | 0xC2 | A (top-left) | Maximum temperature |
| T2 | 0xC4 | B (top-right) | Maximum temperature |
| T3 | 0xC6 | C (bottom-left) | Maximum temperature |
| T4 | 0xC8 | D (bottom-right) | Maximum temperature |
| T5 | 0xCC | A (top-left) | Burner temperature |
| T6 | 0xCF | B (top-right) | Burner temperature |
| T7 | 0xD2 | C (bottom-left) | Burner temperature |
| T8 | 0xD5 | D (bottom-right) | Burner temperature |

### Decoding Formula

Convert 13-bit raw value to Celsius:

```
Temperature (°C) = (rawValue × 0.05) - 20
```

**Range:** -20°C to +388.95°C with 0.05°C resolution

### Decoding Example (Swift)

```swift
func decodeTemperatures(from data: Data) -> [Double] {
    guard data.count >= 13 else { return [] }

    var temperatures: [Double] = []
    var bitPosition = 0

    for _ in 0..<8 {
        var rawValue: UInt16 = 0

        // Extract 13 bits starting at bitPosition
        for bit in 0..<13 {
            let byteIndex = (bitPosition + bit) / 8
            let bitInByte = 7 - ((bitPosition + bit) % 8)

            if (data[byteIndex] & (1 << bitInByte)) != 0 {
                rawValue |= (1 << (12 - bit))
            }
        }
        bitPosition += 13

        // Convert to Celsius
        let celsius = (Double(rawValue) * 0.05) - 20.0
        temperatures.append(celsius)
    }

    return temperatures
}

// Usage with advertising data (offset 7 for temperature bytes)
let tempData = manufacturerData.subdata(in: 7..<20)
let temps = decodeTemperatures(from: tempData)
// temps[0] = Amax, temps[1] = Bmax, temps[2] = Cmax, temps[3] = Dmax
// temps[4] = Aburnert, temps[5] = Bburnert, temps[6] = Cburnert, temps[7] = Dburnert
```

---

## GATT Service

For active connections with notifications.

### Service UUID

```
00000100-CAAB-3792-3D44-97AE51C1407A
```

### Probe Status Characteristic

| Property | Value |
|----------|-------|
| UUID | `00000101-CAAB-3792-3D44-97AE51C1407A` |
| Properties | Read, Notify |
| Value Length | 20 bytes |

### Enabling Notifications

1. Connect to the device
2. Discover services and characteristics
3. Write `0x01 0x00` to the CCCD (Client Characteristic Configuration Descriptor)
4. Receive notifications on each temperature update

```swift
// Enable notifications
let cccdUUID = CBUUID(string: "2902")
peripheral.setNotifyValue(true, for: probeStatusCharacteristic)
```

### Notification Data Format

The characteristic value contains the same temperature data as the advertising packet (13 bytes of packed temperatures at offset 0).

---

## Connection Management

### Connection Parameters

| Parameter | Value |
|-----------|-------|
| Max Connections | 3 simultaneous |
| Connection Interval | 60-100ms |
| Supervision Timeout | 4 seconds |

### Advertising Behavior

- **< 3 connections:** Connectable advertising (ADV_IND)
- **= 3 connections:** Advertising stops until a client disconnects

### No Pairing Required

The device uses open (non-secure) connections. No pairing or bonding is required.

---

## Complete Client Example (Swift/iOS)

```swift
import CoreBluetooth

class ThermoHoodBLEClient: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    static let vendorId: UInt16 = 0x09C7
    static let productType: UInt8 = 0x04
    static let serviceUUID = CBUUID(string: "00000100-CAAB-3792-3D44-97AE51C1407A")
    static let characteristicUUID = CBUUID(string: "00000101-CAAB-3792-3D44-97AE51C1407A")

    var centralManager: CBCentralManager!
    var thermoHoodPeripheral: CBPeripheral?

    struct Temperatures {
        var aMax: Double = 0
        var bMax: Double = 0
        var cMax: Double = 0
        var dMax: Double = 0
        var aBurner: Double = 0
        var bBurner: Double = 0
        var cBurner: Double = 0
        var dBurner: Double = 0
    }

    var latestTemperatures = Temperatures()

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Scanning

    func startScanning() {
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {

        guard let mfrData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              mfrData.count >= 24 else { return }

        // Check vendor ID and product type
        let vendorId = UInt16(mfrData[0]) | (UInt16(mfrData[1]) << 8)
        let productType = mfrData[2]

        guard vendorId == Self.vendorId && productType == Self.productType else { return }

        // Extract serial number
        let serial = UInt32(mfrData[3]) | (UInt32(mfrData[4]) << 8) |
                     (UInt32(mfrData[5]) << 16) | (UInt32(mfrData[6]) << 24)

        // Decode temperatures from advertising data
        let tempData = mfrData.subdata(in: 7..<20)
        let temps = decodeTemperatures(from: tempData)

        if temps.count == 8 {
            latestTemperatures.aMax = temps[0]
            latestTemperatures.bMax = temps[1]
            latestTemperatures.cMax = temps[2]
            latestTemperatures.dMax = temps[3]
            latestTemperatures.aBurner = temps[4]
            latestTemperatures.bBurner = temps[5]
            latestTemperatures.cBurner = temps[6]
            latestTemperatures.dBurner = temps[7]

            print("ThermoHood [\(String(format: "%08X", serial))]:")
            print("  Max temps: A=\(temps[0])°C B=\(temps[1])°C C=\(temps[2])°C D=\(temps[3])°C")
            print("  Burners:   A=\(temps[4])°C B=\(temps[5])°C C=\(temps[6])°C D=\(temps[7])°C")
        }

        // Optionally connect for notifications
        if thermoHoodPeripheral == nil {
            thermoHoodPeripheral = peripheral
            peripheral.delegate = self
            centralManager.connect(peripheral, options: nil)
        }
    }

    // MARK: - Temperature Decoding

    func decodeTemperatures(from data: Data) -> [Double] {
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

            let celsius = (Double(rawValue) * 0.05) - 20.0
            temperatures.append(celsius)
        }

        return temperatures
    }

    // MARK: - Connection & GATT

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to ThermoHood")
        peripheral.discoverServices([Self.serviceUUID])
    }

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
            peripheral.setNotifyValue(true, for: char)
            print("Enabled notifications for probe status")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == Self.characteristicUUID,
              let data = characteristic.value else { return }

        let temps = decodeTemperatures(from: data)
        if temps.count == 8 {
            latestTemperatures.aMax = temps[0]
            latestTemperatures.bMax = temps[1]
            latestTemperatures.cMax = temps[2]
            latestTemperatures.dMax = temps[3]
            latestTemperatures.aBurner = temps[4]
            latestTemperatures.bBurner = temps[5]
            latestTemperatures.cBurner = temps[6]
            latestTemperatures.dBurner = temps[7]
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        }
    }
}
```

---

## Quadrant Layout Reference

The thermal camera image is divided into 4 quadrants:

```
     0          Xsplit           80
   0 ┌────────────┬────────────────┐
     │            │                │
     │     A      │       B        │
     │  (top-left)│   (top-right)  │
     │            │                │
Ysplit├────────────┼────────────────┤
     │            │                │
     │     C      │       D        │
     │(bottom-left)│(bottom-right) │
     │            │                │
  62 └────────────┴────────────────┘
```

**Default split:** Xsplit=40, Ysplit=31 (centered)

---

## Device Identification

The device can be uniquely identified by its Bluetooth MAC address. This allows clients to confirm they're communicating with the same physical device over both BLE and WiFi.

### BLE Serial Number

The 4-byte serial number in the advertising data (offset 3-6) contains the last 4 bytes of the BT MAC address in little-endian format.

**Example**: For BT MAC `D8:3B:DA:4A:2D:B6`:
- Serial bytes: `[0xB6, 0x2D, 0x4A, 0xDA]` (little-endian)
- Serial as uint32: `0xDA4A2DB6`

### WiFi/TCP Correlation

The same BT MAC is available via TCP registers `0xE0-0xE5` (see protocol.md). To match a BLE device to a WiFi device:

```swift
// BLE: Extract serial from advertising data (offset 3-6, little-endian)
let bleSerial = UInt32(mfrData[3]) | (UInt32(mfrData[4]) << 8) |
                (UInt32(mfrData[5]) << 16) | (UInt32(mfrData[6]) << 24)

// WiFi: Read registers 0xE2-0xE5 and construct same value
let wifiSerial = UInt32(reg0xE2) << 24 | UInt32(reg0xE3) << 16 |
                 UInt32(reg0xE4) << 8 | UInt32(reg0xE5)

// Match if equal
if bleSerial == wifiSerial {
    // Same device
}
```

---

## Notes

- Temperature values are updated on every thermal frame (~25 Hz)
- BLE advertising is updated at the same rate
- The device can be monitored passively (no connection) or actively (with connection)
- Passive monitoring via advertising is recommended for battery-powered clients
- All temperature values are in Celsius
- Raw sensor values from the thermal camera are in decikelvin (dK) internally
