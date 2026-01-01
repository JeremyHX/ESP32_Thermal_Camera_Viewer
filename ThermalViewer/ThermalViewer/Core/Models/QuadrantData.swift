import Foundation

@Observable
class QuadrantData {
    var xSplit: Int = 40
    var ySplit: Int = 31

    var aMax: UInt16 = 0
    var aCenter: UInt16 = 0
    var bMax: UInt16 = 0
    var bCenter: UInt16 = 0
    var cMax: UInt16 = 0
    var cCenter: UInt16 = 0
    var dMax: UInt16 = 0
    var dCenter: UInt16 = 0

    /// Update from RRSE response
    func update(from registerValues: [UInt8: UInt16]) {
        if let val = registerValues[ThermalProtocol.regXSplit] { xSplit = Int(val) }
        if let val = registerValues[ThermalProtocol.regYSplit] { ySplit = Int(val) }
        if let val = registerValues[ThermalProtocol.regAMax] { aMax = val }
        if let val = registerValues[ThermalProtocol.regACenter] { aCenter = val }
        if let val = registerValues[ThermalProtocol.regBMax] { bMax = val }
        if let val = registerValues[ThermalProtocol.regBCenter] { bCenter = val }
        if let val = registerValues[ThermalProtocol.regCMax] { cMax = val }
        if let val = registerValues[ThermalProtocol.regCCenter] { cCenter = val }
        if let val = registerValues[ThermalProtocol.regDMax] { dMax = val }
        if let val = registerValues[ThermalProtocol.regDCenter] { dCenter = val }
    }
}

enum Quadrant: String, CaseIterable, Identifiable {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"

    var id: String { rawValue }

    func maxValue(from data: QuadrantData) -> UInt16 {
        switch self {
        case .a: return data.aMax
        case .b: return data.bMax
        case .c: return data.cMax
        case .d: return data.dMax
        }
    }

    func centerValue(from data: QuadrantData) -> UInt16 {
        switch self {
        case .a: return data.aCenter
        case .b: return data.bCenter
        case .c: return data.cCenter
        case .d: return data.dCenter
        }
    }
}

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius = "°C"
    case fahrenheit = "°F"

    var id: String { rawValue }

    func format(_ raw: UInt16) -> String {
        switch self {
        case .celsius:
            return String(format: "%.1f°C", ThermalFrame.rawToCelsius(raw))
        case .fahrenheit:
            return String(format: "%.1f°F", ThermalFrame.rawToFahrenheit(raw))
        }
    }
}
