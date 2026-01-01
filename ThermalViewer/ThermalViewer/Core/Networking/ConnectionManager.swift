import Foundation
import Network

@Observable
class ConnectionManager {
    let frameConnection = FrameStreamConnection()
    let commandConnection = CommandConnection()
    let quadrantData = QuadrantData()

    var host: String = ""
    var currentFrame: ThermalFrame?
    var frameCount: Int = 0
    var fps: Int = 0

    private var fpsTimer: Timer?
    private var frameTimestamps: [Date] = []
    private var quadrantPollTimer: Timer?
    private var reconnectTask: Task<Void, Never>?

    var isConnected: Bool {
        frameConnection.state == .ready && commandConnection.state == .ready
    }

    var isConnecting: Bool {
        let frameConnecting = [.preparing, .setup].contains(where: { frameConnection.state == $0 })
        let cmdConnecting = [.preparing, .setup].contains(where: { commandConnection.state == $0 })
        return frameConnecting || cmdConnecting
    }

    init() {
        setupCallbacks()
    }

    private func setupCallbacks() {
        frameConnection.onFrameReceived = { [weak self] frame in
            self?.handleFrame(frame)
        }

        commandConnection.onQuadrantDataReceived = { [weak self] results in
            self?.quadrantData.update(from: results)
        }
    }

    func connect(to host: String) {
        self.host = host
        reconnectTask?.cancel()

        frameConnection.connect(host: host)
        commandConnection.connect(host: host)

        // Start quadrant polling after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startQuadrantPolling()
        }
    }

    func disconnect() {
        reconnectTask?.cancel()
        stopQuadrantPolling()
        frameConnection.disconnect()
        commandConnection.disconnect()
        frameCount = 0
        fps = 0
        currentFrame = nil
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
