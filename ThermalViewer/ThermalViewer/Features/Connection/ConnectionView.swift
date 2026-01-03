import SwiftUI

struct ConnectionView: View {
    @Environment(ConnectionManager.self) private var connectionManager
    @Binding var initialTab: AppTab
    @State private var ipAddress: String = "192.168.4.213"
    @State private var isConnecting: Bool = false
    @State private var useBluetoothConnection: Bool = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon/title
            VStack(spacing: 16) {
                Image("VibeCuisine")
                    .font(.system(size: 80))
                    .foregroundColor(.cyan)

                Text("Thermal Viewer")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Connect to ESP32 Thermal Camera")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Connection form
            VStack(spacing: 20) {
                // Connection type selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connection Type")
                        .font(.headline)

                    Picker("Connection", selection: $useBluetoothConnection) {
                        Text("WiFi").tag(false)
                        Text("Bluetooth").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                }

                // IP Address (WiFi only)
                if !useBluetoothConnection {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ESP32 IP Address")
                            .font(.headline)

                        TextField("192.168.4.213", text: $ipAddress)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: 300)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    // Mode selector (WiFi only - BLE is Simple mode only)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Start In")
                            .font(.headline)

                        Picker("Mode", selection: $initialTab) {
                            Text("Simple (Gauges)").tag(AppTab.simple)
                            Text("Advanced (Thermal)").tag(AppTab.advanced)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 300)
                    }
                } else {
                    // BLE info
                    VStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)

                        Text("Bluetooth scans for nearby ThermoHood devices")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Text("Simple mode only (no thermal image)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: 300)
                    .padding(.vertical, 8)
                }

                Button {
                    connect()
                } label: {
                    if isConnecting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(width: 20, height: 20)
                    } else {
                        Label("Connect", systemImage: useBluetoothConnection ? "antenna.radiowaves.left.and.right" : "wifi")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled((!useBluetoothConnection && ipAddress.isEmpty) || isConnecting)
            }
            .padding(32)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)

            // Connection status
            connectionStatus

            Spacer()

            // Info footer
            if useBluetoothConnection {
                Text("BLE advertising mode")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(initialTab == .simple ? "Port: 3334 (commands only)" : "Ports: 3333 (frames), 3334 (commands)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onChange(of: connectionManager.isConnected) { _, isConnected in
            if isConnected {
                isConnecting = false
            }
        }
        .onChange(of: connectionManager.commandConnection.state) { _, state in
            if case .failed = state {
                isConnecting = false
            }
        }
        .onChange(of: useBluetoothConnection) { _, useBLE in
            // Force Simple mode when using Bluetooth
            if useBLE {
                initialTab = .simple
            }
        }
    }

    private var connectionStatus: some View {
        Group {
            if isConnecting {
                HStack {
                    ProgressView()
                    if useBluetoothConnection {
                        Text("Scanning for ThermoHood...")
                    } else {
                        Text("Connecting to \(ipAddress)...")
                    }
                }
                .foregroundColor(.secondary)
            } else if !useBluetoothConnection, case .failed(let error) = connectionManager.commandConnection.state {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text("Connection failed: \(error.localizedDescription)")
                        .foregroundColor(.red)
                }
            } else if useBluetoothConnection && !connectionManager.bleManager.isBluetoothAvailable {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Bluetooth is not available")
                        .foregroundColor(.orange)
                }
            }
        }
        .font(.subheadline)
    }

    private func connect() {
        isConnecting = true

        if useBluetoothConnection {
            initialTab = .simple  // BLE only supports Simple mode
            connectionManager.connectBLE()

            // Timeout after 15 seconds for BLE scanning
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                if isConnecting && !connectionManager.isConnected {
                    isConnecting = false
                }
            }
        } else {
            // WiFi connection
            let withFrameStream = (initialTab == .advanced)
            connectionManager.connect(to: ipAddress, withFrameStream: withFrameStream)

            // Timeout after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if isConnecting && !connectionManager.isConnected {
                    isConnecting = false
                }
            }
        }
    }
}
