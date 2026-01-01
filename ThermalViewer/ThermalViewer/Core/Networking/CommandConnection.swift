import Foundation
import Network

@Observable
class CommandConnection {
    private var connection: NWConnection?
    private var receiveBuffer = Data()

    var state: NWConnection.State = .setup
    var onQuadrantDataReceived: (([UInt8: UInt16]) -> Void)?

    func connect(host: String) {
        disconnect()

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: ThermalProtocol.commandPort)!
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
        receiveBuffer.removeAll()
        DispatchQueue.main.async {
            self.state = .cancelled
        }
    }

    // MARK: - Send Commands

    func writeRegister(address: UInt8, value: UInt8) {
        let packet = ThermalProtocol.buildWREG(address: address, value: value)
        send(packet)
    }

    func writeRegister16(address: UInt8, value: UInt16) {
        let packet = ThermalProtocol.buildWREG16(address: address, value: value)
        send(packet)
    }

    func readQuadrantRegisters() {
        let packet = ThermalProtocol.buildRRSE(addresses: ThermalProtocol.quadrantRegisters)
        send(packet)
    }

    private func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("Send error: \(error)")
            }
        })
    }

    // MARK: - Receive

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
        receiveBuffer.append(data)

        // Process protocol packets
        while let packetStart = ThermalProtocol.findPacketStart(in: receiveBuffer) {
            let packetBuffer = receiveBuffer.suffix(from: receiveBuffer.startIndex + packetStart)

            guard let (command, payload, totalLength) = ThermalProtocol.parsePacket(Data(packetBuffer)) else {
                break  // Incomplete packet, wait for more data
            }

            // Handle different commands
            switch command {
            case "RRSE":
                let results = ThermalProtocol.parseRRSEResponse(payload)
                DispatchQueue.main.async { [weak self] in
                    self?.onQuadrantDataReceived?(results)
                }

            case "RREG":
                // Single register read response
                break

            case "WREG":
                // Write acknowledgment
                break

            default:
                break
            }

            // Remove processed packet from buffer
            let removeCount = packetStart + totalLength
            receiveBuffer.removeFirst(removeCount)
        }
    }
}
