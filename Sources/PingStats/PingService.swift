import Foundation
import Network

struct PingResult {
    let latencyMs: Double?
    let errorMessage: String?
}

enum PingService {
    static func probe(address: String, timeout: TimeInterval) async -> PingResult {
        switch ProbeAddress.parse(address) {
        case .ping(let host):
            return await ping(host: host, timeout: timeout)
        case .tcp(let host, let port):
            return await tcpPing(host: host, port: port, timeout: timeout)
        case .invalid(let message):
            return PingResult(latencyMs: nil, errorMessage: message)
        }
    }

    static func ping(host: String, timeout: TimeInterval) async -> PingResult {
        let start = Date()

        return await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let continuationBox = PingContinuationBox(continuation)

            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            process.arguments = [
                "-c", "1",
                "-W", "\(Int((timeout * 1000).rounded()))",
                host
            ]
            process.standardOutput = pipe
            process.standardError = pipe

            process.terminationHandler = { finishedProcess in
                let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""

                if finishedProcess.terminationStatus == 0 {
                    let parsedLatency = parseLatency(from: output)
                    let latency = parsedLatency ?? Date().timeIntervalSince(start) * 1000
                    continuationBox.resume(PingResult(latencyMs: latency, errorMessage: nil))
                } else {
                    let message = output
                        .split(separator: "\n")
                        .last
                        .map(String.init) ?? "Ping failed"
                    continuationBox.resume(PingResult(latencyMs: nil, errorMessage: message))
                }
            }

            do {
                try process.run()
            } catch {
                continuationBox.resume(PingResult(latencyMs: nil, errorMessage: error.localizedDescription))
                return
            }

            Task {
                try? await Task.sleep(for: .seconds(timeout))
                if process.isRunning {
                    process.terminate()
                    continuationBox.resume(PingResult(latencyMs: nil, errorMessage: "Timeout"))
                }
            }
        }
    }

    private static func parseLatency(from output: String) -> Double? {
        guard let range = output.range(of: "time=") else { return nil }
        let suffix = output[range.upperBound...]
        let number = suffix.prefix { character in
            character.isNumber || character == "."
        }
        return Double(number)
    }

    private static func tcpPing(host: String, port: UInt16, timeout: TimeInterval) async -> PingResult {
        let start = Date()

        return await withCheckedContinuation { continuation in
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: PingResult(latencyMs: nil, errorMessage: "Invalid port"))
                return
            }

            let continuationBox = PingContinuationBox(continuation)
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let queue = DispatchQueue(label: "dev.pingstats.tcping.\(host).\(port)")

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let latency = Date().timeIntervalSince(start) * 1000
                    connection.cancel()
                    continuationBox.resume(PingResult(latencyMs: latency, errorMessage: nil))
                case .failed(let error):
                    connection.cancel()
                    continuationBox.resume(PingResult(latencyMs: nil, errorMessage: error.localizedDescription))
                case .waiting(let error):
                    continuationBox.resume(PingResult(latencyMs: nil, errorMessage: error.localizedDescription))
                    connection.cancel()
                default:
                    break
                }
            }

            connection.start(queue: queue)

            Task {
                try? await Task.sleep(for: .seconds(timeout))
                connection.cancel()
                continuationBox.resume(PingResult(latencyMs: nil, errorMessage: "Timeout"))
            }
        }
    }
}

private enum ProbeAddress {
    case ping(String)
    case tcp(String, UInt16)
    case invalid(String)

    static func parse(_ rawAddress: String) -> ProbeAddress {
        let address = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            return .invalid("Address is empty")
        }

        guard let separator = address.lastIndex(of: ":") else {
            return .ping(address)
        }

        let host = String(address[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let portText = String(address[address.index(after: separator)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !host.isEmpty, let port = UInt16(portText), port > 0 else {
            return .invalid("Use host:port with a port from 1 to 65535")
        }

        return .tcp(host, port)
    }
}

private final class PingContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<PingResult, Never>

    init(_ continuation: CheckedContinuation<PingResult, Never>) {
        self.continuation = continuation
    }

    func resume(_ result: PingResult) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: result)
    }
}
