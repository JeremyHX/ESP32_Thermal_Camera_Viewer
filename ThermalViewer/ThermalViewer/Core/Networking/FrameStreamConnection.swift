import Foundation
import Network

@Observable
class FrameStreamConnection {
    private var connection: NWConnection?
    private var frameBuffer = Data()

    var state: NWConnection.State = .setup
    var onFrameReceived: ((ThermalFrame) -> Void)?

    func connect(host: String) {
        disconnect()

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: ThermalProtocol.framePort)!
        )

        connection = NWConnection(to: endpoint, using: .tcp)

        connection?.stateUpdateHandler = { [weak self] newState in
            DispatchQueue.main.async {
                self?.state = newState
            }
            if newState == .ready {
                self?.startReceiving()
            }
        }

        connection?.start(queue: .global(qos: .userInteractive))
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        frameBuffer.removeAll()
        DispatchQueue.main.async {
            self.state = .cancelled
        }
    }

    private func startReceiving() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data {
                self?.processReceivedData(data)
            }

            if !isComplete && error == nil {
                self?.startReceiving()
            }
        }
    }

    private func processReceivedData(_ data: Data) {
        frameBuffer.append(data)

        // Extract complete frames (10,240 bytes each)
        while frameBuffer.count >= ThermalProtocol.tcpFrameSize {
            let frameData = frameBuffer.prefix(ThermalProtocol.tcpFrameSize)
            frameBuffer.removeFirst(ThermalProtocol.tcpFrameSize)

            if let frame = ThermalFrame(data: Data(frameData)) {
                DispatchQueue.main.async { [weak self] in
                    self?.onFrameReceived?(frame)
                }
            }
        }
    }
}
