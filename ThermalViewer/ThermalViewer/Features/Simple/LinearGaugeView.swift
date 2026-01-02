import SwiftUI

struct LinearGaugeView: View {
    let label: String
    let temperature: Double  // in Celsius
    let temperatureUnit: TemperatureUnit

    private let minTemp: Double = 0
    private let maxTemp: Double = 300
    private let lowThreshold: Double = 180
    private let highThreshold: Double = 250

    private var displayTemperature: String {
        switch temperatureUnit {
        case .celsius:
            return String(format: "%.1f°C", temperature)
        case .fahrenheit:
            let fahrenheit = temperature * 9.0 / 5.0 + 32.0
            return String(format: "%.1f°F", fahrenheit)
        }
    }

    private var fillFraction: Double {
        let clamped = max(minTemp, min(maxTemp, temperature))
        return clamped / maxTemp
    }

    private var barColor: Color {
        if temperature < lowThreshold {
            return .blue
        } else if temperature < highThreshold {
            return .green
        } else {
            return .red
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Quadrant label
            Text(label)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            // Temperature value
            Text(displayTemperature)
                .font(.system(size: 42, weight: .semibold, design: .monospaced))
                .foregroundColor(barColor)

            // Gauge bar
            gaugeBar

            // Scale labels
            scaleLabels
        }
        .padding(20)
        .background(Color.black.opacity(0.3))
        .cornerRadius(16)
    }

    private var gaugeBar: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height: CGFloat = 24

            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: height)

                // Colored zones background
                HStack(spacing: 0) {
                    // Blue zone (0-180)
                    Rectangle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: width * (lowThreshold / maxTemp))

                    // Green zone (180-250)
                    Rectangle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: width * ((highThreshold - lowThreshold) / maxTemp))

                    // Red zone (250-300)
                    Rectangle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: width * ((maxTemp - highThreshold) / maxTemp))
                }
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: height / 2))

                // Fill bar
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(barColor)
                    .frame(width: max(height, width * fillFraction), height: height)
                    .animation(.easeOut(duration: 0.3), value: fillFraction)

                // Threshold markers
                thresholdMarkers(width: width, height: height)
            }
        }
        .frame(height: 24)
    }

    private func thresholdMarkers(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // 180°C marker
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 2, height: height + 8)
                .offset(x: width * (lowThreshold / maxTemp) - 1)

            // 250°C marker
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 2, height: height + 8)
                .offset(x: width * (highThreshold / maxTemp) - 1)
        }
    }

    private var scaleLabels: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack(alignment: .leading) {
                // 0 label (left edge)
                Text("0")
                    .position(x: 0, y: 8)

                // 180 label (aligned with marker)
                Text("180")
                    .position(x: width * (lowThreshold / maxTemp), y: 8)

                // 250 label (aligned with marker)
                Text("250")
                    .position(x: width * (highThreshold / maxTemp), y: 8)

                // 300°C label (right edge)
                Text("300°C")
                    .position(x: width, y: 8)
            }
            .font(.system(size: 12))
            .foregroundColor(.gray)
        }
        .frame(height: 16)
    }
}

#Preview {
    VStack(spacing: 20) {
        LinearGaugeView(label: "A", temperature: 150, temperatureUnit: .celsius)
        LinearGaugeView(label: "B", temperature: 200, temperatureUnit: .celsius)
        LinearGaugeView(label: "C", temperature: 260, temperatureUnit: .celsius)
        LinearGaugeView(label: "D", temperature: 45, temperatureUnit: .celsius)
    }
    .padding()
    .background(Color.black)
}
