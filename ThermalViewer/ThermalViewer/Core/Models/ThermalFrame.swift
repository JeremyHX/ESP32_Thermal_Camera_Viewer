import Foundation

struct ThermalFrame {
    let width: Int
    let height: Int
    let pixels: [UInt16]  // 80x62 = 4960 pixels (image only, no header)
    let minValue: UInt16
    let maxValue: UInt16
    let frameNumber: UInt16
    let dieTemperature: UInt16  // in milliKelvin
    let headerMin: UInt16
    let headerMax: UInt16

    /// Initialize from raw TCP frame data (10,240 bytes = 80x64 pixels)
    init?(data: Data) {
        guard data.count >= ThermalProtocol.tcpFrameSize else { return nil }

        self.width = ThermalProtocol.frameWidth
        self.height = ThermalProtocol.imageHeight

        // Parse header (first 2 rows = 160 pixels = 320 bytes)
        // Header indices: [0]=frame#, [1]=VDD, [2]=die temp, [5]=max, [6]=min
        let headerPixels = data.withUnsafeBytes { buffer -> [UInt16] in
            let uint16Buffer = buffer.bindMemory(to: UInt16.self)
            return Array(uint16Buffer.prefix(ThermalProtocol.frameWidth * ThermalProtocol.headerRows))
        }

        self.frameNumber = headerPixels.count > 0 ? headerPixels[0] : 0
        self.dieTemperature = headerPixels.count > 2 ? headerPixels[2] : 0
        self.headerMax = headerPixels.count > 5 ? headerPixels[5] : 0
        self.headerMin = headerPixels.count > 6 ? headerPixels[6] : 0

        // Parse image data (rows 2-63 = 62 rows = 4960 pixels)
        let imageStart = ThermalProtocol.headerSize
        let imageData = data[imageStart..<(imageStart + ThermalProtocol.imageSize)]

        self.pixels = imageData.withUnsafeBytes { buffer -> [UInt16] in
            let uint16Buffer = buffer.bindMemory(to: UInt16.self)
            return Array(uint16Buffer)
        }

        // Calculate actual min/max from image pixels
        self.minValue = pixels.min() ?? 0
        self.maxValue = pixels.max() ?? 65535
    }

    /// Get pixel value at (x, y) coordinate
    func pixel(at x: Int, y: Int) -> UInt16? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        return pixels[y * width + x]
    }

    /// Convert raw value to Celsius
    static func rawToCelsius(_ raw: UInt16) -> Double {
        return Double(raw) * 0.0984 - 265.82
    }

    /// Convert raw value to Fahrenheit
    static func rawToFahrenheit(_ raw: UInt16) -> Double {
        let celsius = rawToCelsius(raw)
        return celsius * 9.0 / 5.0 + 32.0
    }
}
