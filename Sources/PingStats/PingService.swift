import Foundation

struct PingResult {
    let latencyMs: Double?
    let errorMessage: String?
}

enum PingService {
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
