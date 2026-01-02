import SwiftUI

struct ConnectionView: View {
    @Environment(ConnectionManager.self) private var connectionManager
    @Binding var initialTab: AppTab
    @State private var ipAddress: String = "192.168.4.213"
    @State private var isConnecting: Bool = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon/title
            VStack(spacing: 16) {
                Image(systemName: "camera.viewfinder")
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

                // Mode selector
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

                Button {
                    connect()
                } label: {
                    if isConnecting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(width: 20, height: 20)
                    } else {
                        Label("Connect", systemImage: "wifi")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(ipAddress.isEmpty || isConnecting)
            }
            .padding(32)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)

            // Connection status
            connectionStatus

            Spacer()

            // Info footer
            Text(initialTab == .simple ? "Port: 3334 (commands only)" : "Ports: 3333 (frames), 3334 (commands)")
                .font(.caption)
                .foregroundColor(.secondary)
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
    }

    private var connectionStatus: some View {
        Group {
            if isConnecting {
                HStack {
                    ProgressView()
                    Text("Connecting to \(ipAddress)...")
                }
                .foregroundColor(.secondary)
            } else if case .failed(let error) = connectionManager.commandConnection.state {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text("Connection failed: \(error.localizedDescription)")
                        .foregroundColor(.red)
                }
            }
        }
        .font(.subheadline)
    }

    private func connect() {
        isConnecting = true
        // Connect with frame stream only if starting in Advanced mode
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
