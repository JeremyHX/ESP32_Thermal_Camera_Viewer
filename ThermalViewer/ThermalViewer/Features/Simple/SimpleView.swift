import SwiftUI

struct SimpleView: View {
    @Environment(ConnectionManager.self) private var connectionManager
    @State private var temperatureUnit: TemperatureUnit = .celsius
    @State private var useMaxTemperature: Bool = true
    @State private var alertTracker = TemperatureAlertTracker()

    // Convert raw sensor values to Celsius
    private func toCelsius(_ raw: UInt16) -> Double {
        return Double(raw) * 0.0984 - 265.82
    }

    // Get temperature for a quadrant based on useMaxTemperature setting
    private func temperatureForQuadrant(_ quadrant: String) -> Double {
        let data = connectionManager.quadrantData
        switch quadrant {
        case "A": return toCelsius(useMaxTemperature ? data.aMax : data.aCenter)
        case "B": return toCelsius(useMaxTemperature ? data.bMax : data.bCenter)
        case "C": return toCelsius(useMaxTemperature ? data.cMax : data.cCenter)
        case "D": return toCelsius(useMaxTemperature ? data.dMax : data.dCenter)
        default: return 0
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Main gauge grid
            gaugeGrid
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Side panel
            sidePanel
                .frame(width: 200)
                .background(Color(.systemBackground).opacity(0.95))
        }
        .background(Color.black)
        // Monitor both max and center values for alerts
        .onChange(of: connectionManager.quadrantData.aMax) { _, _ in
            alertTracker.checkTemperature(quadrant: "A", temperature: temperatureForQuadrant("A"))
        }
        .onChange(of: connectionManager.quadrantData.aCenter) { _, _ in
            alertTracker.checkTemperature(quadrant: "A", temperature: temperatureForQuadrant("A"))
        }
        .onChange(of: connectionManager.quadrantData.bMax) { _, _ in
            alertTracker.checkTemperature(quadrant: "B", temperature: temperatureForQuadrant("B"))
        }
        .onChange(of: connectionManager.quadrantData.bCenter) { _, _ in
            alertTracker.checkTemperature(quadrant: "B", temperature: temperatureForQuadrant("B"))
        }
        .onChange(of: connectionManager.quadrantData.cMax) { _, _ in
            alertTracker.checkTemperature(quadrant: "C", temperature: temperatureForQuadrant("C"))
        }
        .onChange(of: connectionManager.quadrantData.cCenter) { _, _ in
            alertTracker.checkTemperature(quadrant: "C", temperature: temperatureForQuadrant("C"))
        }
        .onChange(of: connectionManager.quadrantData.dMax) { _, _ in
            alertTracker.checkTemperature(quadrant: "D", temperature: temperatureForQuadrant("D"))
        }
        .onChange(of: connectionManager.quadrantData.dCenter) { _, _ in
            alertTracker.checkTemperature(quadrant: "D", temperature: temperatureForQuadrant("D"))
        }
        .onDisappear {
            alertTracker.reset()
        }
    }

    private var gaugeGrid: some View {
        let flipH = connectionManager.flipHorizontally
        let flipV = connectionManager.flipVertically

        // Determine which quadrant appears in each position based on flip settings
        // Original layout: A=top-left, B=top-right, C=bottom-left, D=bottom-right
        let topLeftLabel: String = {
            switch (flipH, flipV) {
            case (false, false): return "A"
            case (true, false):  return "B"
            case (false, true):  return "C"
            case (true, true):   return "D"
            }
        }()

        let topRightLabel: String = {
            switch (flipH, flipV) {
            case (false, false): return "B"
            case (true, false):  return "A"
            case (false, true):  return "D"
            case (true, true):   return "C"
            }
        }()

        let bottomLeftLabel: String = {
            switch (flipH, flipV) {
            case (false, false): return "C"
            case (true, false):  return "D"
            case (false, true):  return "A"
            case (true, true):   return "B"
            }
        }()

        let bottomRightLabel: String = {
            switch (flipH, flipV) {
            case (false, false): return "D"
            case (true, false):  return "C"
            case (false, true):  return "B"
            case (true, true):   return "A"
            }
        }()

        return VStack(spacing: 200) {
            // Top row
            HStack(spacing: 20) {
                LinearGaugeView(
                    label: topLeftLabel,
                    temperature: temperatureForQuadrant(topLeftLabel),
                    temperatureUnit: temperatureUnit
                )

                LinearGaugeView(
                    label: topRightLabel,
                    temperature: temperatureForQuadrant(topRightLabel),
                    temperatureUnit: temperatureUnit
                )
            }

            // Bottom row
            HStack(spacing: 20) {
                LinearGaugeView(
                    label: bottomLeftLabel,
                    temperature: temperatureForQuadrant(bottomLeftLabel),
                    temperatureUnit: temperatureUnit
                )

                LinearGaugeView(
                    label: bottomRightLabel,
                    temperature: temperatureForQuadrant(bottomRightLabel),
                    temperatureUnit: temperatureUnit
                )
            }
        }
        .padding(40)
    }

    private var sidePanel: some View {
        VStack(spacing: 16) {
            Image("VibeCuisine")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)

            // Status header
            statusHeader

            Divider()

            // Temperature unit selector
            VStack(alignment: .leading, spacing: 8) {
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

            Divider()

            // Temperature reading mode
            VStack(alignment: .leading, spacing: 8) {
                Text("Temperature Reading")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Reading", selection: $useMaxTemperature) {
                    Text("Max").tag(true)
                    Text("Center").tag(false)
                }
                .pickerStyle(.segmented)
            }

            Divider()

            // Sound alerts toggle
            soundAlertsToggle

            Divider()

            // BLE auto-connect toggle
            bleAutoConnectToggle

            Divider()

            // Legend
            legendView

            Spacer()

            // Disconnect button
            disconnectButton
        }
        .padding()
    }

    private var soundAlertsToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $alertTracker.soundAlertsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sound Alerts")
                        .font(.subheadline)
                    Text("Plays at 180°C and 250°C")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    private var bleAutoConnectToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            @Bindable var cm = connectionManager
            Toggle(isOn: $cm.bleAutoConnectEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bluetooth Auto-Connect")
                        .font(.subheadline)
                    Text("Faster updates when available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            .onChange(of: connectionManager.bleAutoConnectEnabled) { _, enabled in
                connectionManager.setBLEAutoConnect(enabled)
            }
        }
    }

    private var statusHeader: some View {
        VStack(spacing: 8) {
            // Data source indicator
            HStack {
                Circle()
                    .fill(connectionManager.isConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)

                if connectionManager.usingBLEData {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.blue)
                    Text("Bluetooth")
                        .font(.headline)
                } else {
                    Image(systemName: "wifi")
                        .foregroundColor(.green)
                    Text("WiFi")
                        .font(.headline)
                }
                Spacer()
            }

            // Show BLE device info if connected
            if connectionManager.usingBLEData, let deviceName = connectionManager.bleDeviceName {
                Text("\(deviceName) • \(connectionManager.bleRSSI) dBm")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !connectionManager.usingBLEData {
                Text("Polling every 1s")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var legendView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Temperature Zones")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Circle().fill(.blue).frame(width: 12, height: 12)
                Text("< 180°C")
                    .font(.caption)
            }

            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 12, height: 12)
                Text("180-250°C")
                    .font(.caption)
            }

            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 12, height: 12)
                Text("> 250°C")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
}
