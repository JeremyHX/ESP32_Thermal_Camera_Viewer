import SwiftUI
import CoreGraphics

struct ThermalCanvasView: View {
    let frame: ThermalFrame?
    let palette: ColorPalette
    let flipHorizontally: Bool
    let flipVertically: Bool

    var body: some View {
        GeometryReader { geometry in
            if let cgImage = renderFrame() {
                Image(decorative: cgImage, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(x: flipHorizontally ? -1 : 1, y: flipVertically ? -1 : 1)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                Rectangle()
                    .fill(Color.black)
                    .overlay(
                        Text("No Signal")
                            .foregroundColor(.gray)
                    )
            }
        }
        .aspectRatio(CGFloat(ThermalProtocol.frameWidth) / CGFloat(ThermalProtocol.imageHeight), contentMode: .fit)
    }

    private func renderFrame() -> CGImage? {
        guard let frame = frame else { return nil }

        let width = ThermalProtocol.frameWidth
        let height = ThermalProtocol.imageHeight

        // Normalize values based on frame min/max
        let minVal = Double(frame.minValue)
        let maxVal = Double(frame.maxValue)
        let range = max(1, maxVal - minVal)

        // Create RGBA buffer
        var rgbaBuffer = [UInt8](repeating: 0, count: width * height * 4)

        for i in 0..<frame.pixels.count {
            let normalized = (Double(frame.pixels[i]) - minVal) / range
            let (r, g, b) = palette.color(for: normalized)

            let offset = i * 4
            rgbaBuffer[offset] = r
            rgbaBuffer[offset + 1] = g
            rgbaBuffer[offset + 2] = b
            rgbaBuffer[offset + 3] = 255
        }

        // Create CGImage from buffer
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let provider = CGDataProvider(data: Data(rgbaBuffer) as CFData) else {
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
