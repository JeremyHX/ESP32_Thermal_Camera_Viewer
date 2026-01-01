import Foundation

enum ThermalProtocol {
    // MARK: - Constants
    static let framePort: UInt16 = 3333
    static let commandPort: UInt16 = 3334

    static let frameWidth = 80
    static let frameHeight = 64
    static let headerRows = 1
    static let imageHeight = 62  // frameHeight - headerRows
    static let bytesPerPixel = 2

    static let tcpFrameSize = frameWidth * frameHeight * bytesPerPixel  // 10,240 bytes
    static let headerSize = frameWidth * headerRows * bytesPerPixel     // 320 bytes
    static let imageSize = frameWidth * imageHeight * bytesPerPixel     // 9,920 bytes

    // MARK: - Quadrant Register Addresses
    static let regXSplit: UInt8 = 0xC0
    static let regYSplit: UInt8 = 0xC1
    static let regAMax: UInt8 = 0xC2
    static let regACenter: UInt8 = 0xC3
    static let regBMax: UInt8 = 0xC4
    static let regBCenter: UInt8 = 0xC5
    static let regCMax: UInt8 = 0xC6
    static let regCCenter: UInt8 = 0xC7
    static let regDMax: UInt8 = 0xC8
    static let regDCenter: UInt8 = 0xC9

    static let quadrantRegisters: [UInt8] = [
        regXSplit, regYSplit,
        regAMax, regACenter,
        regBMax, regBCenter,
        regCMax, regCCenter,
        regDMax, regDCenter
    ]

    // MARK: - Packet Building

    /// Build a protocol packet with format: [3 spaces][#][4-char hex length][command][data][XXXX]
    static func buildPacket(command: String, data: String = "") -> Data {
        let payload = command + data
        let length = payload.count + 4  // +4 for CRC placeholder
        let lengthHex = String(format: "%04X", length)
        let packet = "   #\(lengthHex)\(payload)XXXX"
        return Data(packet.utf8)
    }

    /// Build WREG command to write a value to a register
    static func buildWREG(address: UInt8, value: UInt8) -> Data {
        let addrHex = String(format: "%02X", address)
        let valueHex = String(format: "%02X", value)
        return buildPacket(command: "WREG", data: addrHex + valueHex)
    }

    /// Build WREG command to write a 16-bit value to a register
    static func buildWREG16(address: UInt8, value: UInt16) -> Data {
        let addrHex = String(format: "%02X", address)
        let valueHex = String(format: "%04X", value)
        return buildPacket(command: "WREG", data: addrHex + valueHex)
    }

    /// Build RREG command to read a register
    static func buildRREG(address: UInt8) -> Data {
        let addrHex = String(format: "%02X", address)
        return buildPacket(command: "RREG", data: addrHex)
    }

    /// Build RRSE command to read multiple registers
    static func buildRRSE(addresses: [UInt8]) -> Data {
        let addrData = addresses.map { String(format: "%02X", $0) }.joined()
        return buildPacket(command: "RRSE", data: addrData + "FF")
    }

    // MARK: - Packet Parsing

    /// Find the start of a protocol packet ("   #" pattern)
    static func findPacketStart(in data: Data) -> Int? {
        guard data.count >= 4 else { return nil }
        let bytes = [UInt8](data)  // Convert to array for safe 0-based indexing
        let pattern: [UInt8] = [0x20, 0x20, 0x20, 0x23]  // "   #"
        for i in 0...(bytes.count - 4) {
            if bytes[i] == pattern[0] &&
               bytes[i + 1] == pattern[1] &&
               bytes[i + 2] == pattern[2] &&
               bytes[i + 3] == pattern[3] {
                return i
            }
        }
        return nil
    }

    /// Parse a protocol packet, returns (command, data, totalLength) or nil if incomplete
    static func parsePacket(_ data: Data) -> (command: String, data: Data, totalLength: Int)? {
        guard data.count >= 12 else { return nil }

        let bytes = [UInt8](data)  // Convert to array for safe indexing

        // Check for "   #" prefix
        guard bytes[0] == 0x20, bytes[1] == 0x20, bytes[2] == 0x20, bytes[3] == 0x23 else {
            return nil
        }

        // Parse length (4 hex chars at positions 4-7)
        guard let lengthStr = String(bytes: bytes[4..<8], encoding: .ascii),
              let payloadLen = Int(lengthStr, radix: 16),
              payloadLen >= 8, payloadLen <= 15000 else {
            return nil
        }

        let totalPacketLen = 4 + 4 + payloadLen  // prefix + length + payload
        guard bytes.count >= totalPacketLen else { return nil }

        // Parse command (4 chars at positions 8-11)
        guard let command = String(bytes: bytes[8..<12], encoding: .ascii) else {
            return nil
        }

        // Extract data (excluding command and CRC)
        let dataStart = 12
        let dataEnd = 8 + payloadLen - 4  // -4 for CRC

        // Ensure valid range
        guard dataEnd >= dataStart, dataEnd <= bytes.count else {
            return (command, Data(), totalPacketLen)
        }

        let payloadData = Data(bytes[dataStart..<dataEnd])
        return (command, payloadData, totalPacketLen)
    }

    /// Parse RRSE response data into register values
    static func parseRRSEResponse(_ data: Data) -> [UInt8: UInt16] {
        var results: [UInt8: UInt16] = [:]
        guard let hexString = String(data: data, encoding: .ascii) else {
            return results
        }

        var offset = 0
        while offset < hexString.count {
            guard offset + 2 <= hexString.count else { break }

            let addrStart = hexString.index(hexString.startIndex, offsetBy: offset)
            let addrEnd = hexString.index(addrStart, offsetBy: 2)
            guard let addr = UInt8(hexString[addrStart..<addrEnd], radix: 16) else { break }
            offset += 2

            // Quadrant registers (0xC0-0xC9) are 16-bit, others are 8-bit
            let isQuadrantReg = addr >= 0xC0 && addr <= 0xC9
            let valueLen = isQuadrantReg ? 4 : 2

            guard offset + valueLen <= hexString.count else { break }

            let valueStart = hexString.index(hexString.startIndex, offsetBy: offset)
            let valueEnd = hexString.index(valueStart, offsetBy: valueLen)
            guard let value = UInt16(hexString[valueStart..<valueEnd], radix: 16) else { break }
            offset += valueLen

            results[addr] = value
        }

        return results
    }
}
