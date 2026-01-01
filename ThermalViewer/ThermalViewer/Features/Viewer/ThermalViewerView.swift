import SwiftUI

struct ThermalViewerView: View {
    @Environment(ConnectionManager.self) private var connectionManager
    @State private var selectedPalette: ColorPalette = .default
    @State private var temperatureUnit: TemperatureUnit = .celsius
    @State private var showQuadrants: Bool = true
    @State private var isFlipped: Bool = false
    @State private var showSettings: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // Main thermal view
            thermalDisplay
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Side panel
            sidePanel
                .frame(width: 280)
                .background(Color(.systemBackground).opacity(0.95))
        }
        .background(Color.black)
        .statusBar(hidden: true)
    }

    // MARK: - Thermal Display

    private var thermalDisplay: some View {
        GeometryReader { geometry in
            ZStack {
                // Thermal image
                ThermalCanvasView(
                    frame: connectionManager.currentFrame,
                    palette: selectedPalette,
                    isFlipped: isFlipped
                )

                // Quadrant overlay
                QuadrantOverlayView(
                    quadrantData: connectionManager.quadrantData,
                    showQuadrants: showQuadrants,
                    isFlipped: isFlipped,
                    temperatureUnit: temperatureUnit,
                    onXSplitChanged: connectionManager.setXSplit,
                    onYSplitChanged: connectionManager.setYSplit
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    // MARK: - Side Panel

    private var sidePanel: some View {
        VStack(spacing: 16) {
            // Status header
            statusHeader

            Divider()

            // Temperature range
            temperatureRange

            Divider()

            // Controls
            controlsSection

            Spacer()

            // Disconnect button
            disconnectButton
        }
        .padding()
    }

    private var statusHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(connectionManager.isConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(connectionManager.isConnected ? "Connected" : "Disconnected")
                    .font(.headline)
                Spacer()
            }

            HStack {
                Text("\(connectionManager.fps) FPS")
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Text("Frame: \(connectionManager.frameCount)")
                    .font(.system(.body, design: .monospaced))
            }
            .foregroundColor(.secondary)
        }
    }

    private var temperatureRange: some View {
        VStack(spacing: 8) {
            if let frame = connectionManager.currentFrame {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Min")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(temperatureUnit.format(frame.minValue))
                            .font(.system(.title3, design: .monospaced))
                            .foregroundColor(.cyan)
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text("Max")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(temperatureUnit.format(frame.maxValue))
                            .font(.system(.title3, design: .monospaced))
                            .foregroundColor(.red)
                    }
                }

                // Color gradient bar
                paletteGradientBar
            } else {
                Text("No data")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var paletteGradientBar: some View {
        LinearGradient(
            colors: selectedPalette.previewColors,
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 16)
        .cornerRadius(4)
    }

    private var controlsSection: some View {
        VStack(spacing: 16) {
            // Palette picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Color Palette")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Palette", selection: $selectedPalette) {
                    ForEach(ColorPalette.allCases) { palette in
                        Text(palette.rawValue).tag(palette)
                    }
                }
                .pickerStyle(.menu)
            }

            // Temperature unit
            VStack(alignment: .leading, spacing: 4) {
                Text("Temperature Unit")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Unit", selection: $temperatureUnit) {
                    ForEach(TemperatureUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Toggles
            Toggle("Show Quadrants", isOn: $showQuadrants)
            Toggle("Flip Image", isOn: $isFlipped)

            // Reset quadrants button
            Button("Reset Quadrants") {
                connectionManager.resetQuadrantDefaults()
            }
            .buttonStyle(.bordered)

            // Screenshot button
            Button {
                saveScreenshot()
            } label: {
                Label("Save Screenshot", systemImage: "camera")
            }
            .buttonStyle(.bordered)
        }
    }

    private var disconnectButton: some View {
        Button(role: .destructive) {
            connectionManager.disconnect()
        } label: {
            Label("Disconnect", systemImage: "wifi.slash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    // MARK: - Actions

    private func saveScreenshot() {
        // TODO: Implement screenshot capture
    }
}
