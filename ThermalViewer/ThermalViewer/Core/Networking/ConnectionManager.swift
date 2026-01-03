import Foundation
import Network

@Observable
class ConnectionManager {
    let frameConnection = FrameStreamConnection()
    let commandConnection = CommandConnection()
    let bleManager = BLEManager()
    let quadrantData = QuadrantData()

    var host: String = ""
    var currentFrame: ThermalFrame?
    var frameCount: Int = 0
    var fps: Int = 0
    var frameStreamEnabled: Bool = false

    // BLE hybrid mode settings
    var bleAutoConnectEnabled: Bool = true
    var usingBLEData: Bool = false

    // Display settings (shared across tabs)
    var flipHorizontally: Bool = false
    var flipVertically: Bool = false

    private var fpsTimer: Timer?
    private var frameTimestamps: [Date] = []
    private var quadrantPollTimer: Timer?
    private var reconnectTask: Task<Void, Never>?
    private var lastBLEUpdateTime: Date?

    var isConnected: Bool {
        if frameStreamEnabled {
            return frameConnection.state == .ready && commandConnection.state == .ready
        } else {
            return commandConnection.state == .ready
        }
    }

    var isConnecting: Bool {
        let cmdConnecting = [.preparing, .setup].contains(where: { commandConnection.state == $0 })
        if frameStreamEnabled {
            let frameConnecting = [.preparing, .setup].contains(where: { frameConnection.state == $0 })
            return frameConnecting || cmdConnecting
        }
        return cmdConnecting
    }

    var bleDeviceName: String? {
        bleManager.discoveredDeviceName
    }

    var bleRSSI: Int {
        bleManager.rssi
    }

    var isBLEConnected: Bool {
        bleManager.state == .connected || (bleManager.state == .scanning && bleManager.discoveredDeviceName != nil)
    }

    init() {
        setupCallbacks()
    }

    private func setupCallbacks() {
        frameConnection.onFrameReceived = { [weak self] frame in
            self?.handleFrame(frame)
        }

        commandConnection.onQuadrantDataReceived = { [weak self] results in
            guard let self = self else { return }
            // Only use WiFi data if not receiving BLE data
            if !self.usingBLEData {
                self.quadrantData.update(from: results)
            }
        }

        bleManager.onTemperaturesUpdated = { [weak self] in
            self?.handleBLEUpdate()
        }
    }

    private func handleBLEUpdate() {
        // Mark that we're receiving BLE data
        usingBLEData = true
        lastBLEUpdateTime = Date()

        // Convert BLE temperatures (already in Celsius) to raw sensor values
        // Reverse of: celsius = raw * 0.0984 - 265.82
        // raw = (celsius + 265.82) / 0.0984
        func toRaw(_ celsius: Double) -> UInt16 {
            let raw = (celsius + 265.82) / 0.0984
            return UInt16(max(0, min(65535, raw)))
        }

        quadrantData.aMax = toRaw(bleManager.aMax)
        quadrantData.aCenter = toRaw(bleManager.aCenter)
        quadrantData.bMax = toRaw(bleManager.bMax)
        quadrantData.bCenter = toRaw(bleManager.bCenter)
        quadrantData.cMax = toRaw(bleManager.cMax)
        quadrantData.cCenter = toRaw(bleManager.cCenter)
        quadrantData.dMax = toRaw(bleManager.dMax)
        quadrantData.dCenter = toRaw(bleManager.dCenter)
    }

    /// Connect via WiFi
    func connect(to host: String, withFrameStream: Bool = true) {
        self.host = host
        self.frameStreamEnabled = withFrameStream
        reconnectTask?.cancel()

        if withFrameStream {
            frameConnection.connect(host: host)
        }
        commandConnection.connect(host: host)

        // Start quadrant polling after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startQuadrantPolling()
            // If connecting without frame stream (Simple mode), send POLL to enable ESP32 polling
            if !withFrameStream {
                self?.commandConnection.sendPoll(frequency: 1)
                // Also start BLE scanning if enabled
                self?.startBLEIfEnabled()
            }
        }
    }

    func disconnect() {
        reconnectTask?.cancel()
        stopQuadrantPolling()
        stopBLEScanning()

        frameConnection.disconnect()
        commandConnection.disconnect()

        frameCount = 0
        fps = 0
        currentFrame = nil
        frameStreamEnabled = false
        usingBLEData = false
    }

    /// Enable or disable frame streaming while connected
    /// When disabled, sends POLL 01 to start ESP32 polling at 1Hz
    /// When enabled, sends POLL 00 to stop polling before reconnecting frame stream
    func setFrameStreamEnabled(_ enabled: Bool) {
        guard !host.isEmpty else { return }

        if enabled && !frameStreamEnabled {
            // Exiting Simple view: stop BLE, stop polling, then connect frame stream
            stopBLEScanning()
            commandConnection.sendPoll(frequency: 0)
            // Brief delay to ensure POLL command is processed before frame stream connects
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                self.frameConnection.connect(host: self.host)
                self.frameStreamEnabled = true
            }
        } else if !enabled && frameStreamEnabled {
            // Entering Simple view: disconnect frame stream, then start polling and BLE
            frameConnection.disconnect()
            currentFrame = nil
            frameCount = 0
            fps = 0
            frameStreamEnabled = false
            // Brief delay to ensure frame port is disconnected before sending POLL
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.commandConnection.sendPoll(frequency: 1)
                self?.startBLEIfEnabled()
            }
        }
    }

    // MARK: - BLE Hybrid Mode

    func startBLEIfEnabled() {
        guard bleAutoConnectEnabled else { return }
        guard bleManager.isBluetoothAvailable else { return }

        bleManager.startScanning()

        // Start a timer to detect BLE disconnection (no updates for 2 seconds)
        startBLEWatchdog()
    }

    func stopBLEScanning() {
        bleManager.disconnect()
        usingBLEData = false
        stopBLEWatchdog()
    }

    func setBLEAutoConnect(_ enabled: Bool) {
        bleAutoConnectEnabled = enabled
        if enabled && !frameStreamEnabled && isConnected {
            startBLEIfEnabled()
        } else if !enabled {
            stopBLEScanning()
        }
    }

    private var bleWatchdogTimer: Timer?

    private func startBLEWatchdog() {
        stopBLEWatchdog()
        bleWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkBLEConnection()
        }
    }

    private func stopBLEWatchdog() {
        bleWatchdogTimer?.invalidate()
        bleWatchdogTimer = nil
    }

    private func checkBLEConnection() {
        guard usingBLEData else { return }

        // If no BLE update in 2 seconds, fall back to WiFi
        if let lastUpdate = lastBLEUpdateTime, Date().timeIntervalSince(lastUpdate) > 2.0 {
            usingBLEData = false
        }
    }

    // MARK: - Frame Handling

    private func handleFrame(_ frame: ThermalFrame) {
        currentFrame = frame
        frameCount += 1
        updateFPS()
    }

    private func updateFPS() {
        let now = Date()
        frameTimestamps.append(now)

        // Keep only timestamps from last second
        let oneSecondAgo = now.addingTimeInterval(-1)
        frameTimestamps = frameTimestamps.filter { $0 > oneSecondAgo }

        fps = frameTimestamps.count
    }

    // MARK: - Quadrant Polling

    private func startQuadrantPolling() {
        stopQuadrantPolling()

        // Initial read
        commandConnection.readQuadrantRegisters()

        // Poll every second
        quadrantPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.commandConnection.readQuadrantRegisters()
        }
    }

    private func stopQuadrantPolling() {
        quadrantPollTimer?.invalidate()
        quadrantPollTimer = nil
    }

    // MARK: - Quadrant Controls

    func setXSplit(_ value: Int) {
        let clamped = max(1, min(79, value))
        quadrantData.xSplit = clamped
        commandConnection.writeRegister(address: ThermalProtocol.regXSplit, value: UInt8(clamped))
    }

    func setYSplit(_ value: Int) {
        let clamped = max(1, min(61, value))
        quadrantData.ySplit = clamped
        commandConnection.writeRegister(address: ThermalProtocol.regYSplit, value: UInt8(clamped))
    }

    func resetQuadrantDefaults() {
        setXSplit(40)
        setYSplit(31)
    }
}
