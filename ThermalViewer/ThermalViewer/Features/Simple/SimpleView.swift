import SwiftUI

struct SimpleView: View {
    @Environment(ConnectionManager.self) private var connectionManager
    @State private var temperatureUnit: TemperatureUnit = .celsius
    @State private var alertTracker = TemperatureAlertTracker()

    // Convert raw sensor values to Celsius
    private func toCelsius(_ raw: UInt16) -> Double {
        return Double(raw) * 0.0984 - 265.82
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
        .onChange(of: connectionManager.quadrantData.aMax) { _, newValue in
            alertTracker.checkTemperature(quadrant: "A", temperature: toCelsius(newValue))
        }
        .onChange(of: connectionManager.quadrantData.bMax) { _, newValue in
            alertTracker.checkTemperature(quadrant: "B", temperature: toCelsius(newValue))
        }
        .onChange(of: connectionManager.quadrantData.cMax) { _, newValue in
            alertTracker.checkTemperature(quadrant: "C", temperature: toCelsius(newValue))
        }
        .onChange(of: connectionManager.quadrantData.dMax) { _, newValue in
            alertTracker.checkTemperature(quadrant: "D", temperature: toCelsius(newValue))
        }
        .onDisappear {
            alertTracker.reset()
        }
    }

    private var gaugeGrid: some View {
        let quadrantData = connectionManager.quadrantData

        return VStack(spacing: 200) {
            // Top row: A and B
            HStack(spacing: 20) {
                LinearGaugeView(
                    label: "A",
                    temperature: toCelsius(quadrantData.aMax),
                    temperatureUnit: temperatureUnit
                )

                LinearGaugeView(
                    label: "B",
                    temperature: toCelsius(quadrantData.bMax),
                    temperatureUnit: temperatureUnit
                )
            }

            // Bottom row: C and D
            HStack(spacing: 20) {
                LinearGaugeView(
                    label: "C",
                    temperature: toCelsius(quadrantData.cMax),
                    temperatureUnit: temperatureUnit
                )

                LinearGaugeView(
                    label: "D",
                    temperature: toCelsius(quadrantData.dMax),
                    temperatureUnit: temperatureUnit
                )
            }
        }
        .padding(40)
    }

    private var sidePanel: some View {
        VStack(spacing: 16) {
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

            // Sound alerts toggle
            soundAlertsToggle

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

    private var statusHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(connectionManager.commandConnection.state == .ready ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text("Command Port")
                    .font(.headline)
                Spacer()
            }

            Text("Polling every 1s")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
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
