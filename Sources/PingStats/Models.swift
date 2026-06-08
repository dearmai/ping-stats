import AppKit
import Foundation

enum PingHealth: Int, Codable, CaseIterable {
    case green
    case blue
    case yellow
    case orange
    case red

    var isNormal: Bool {
        self == .green || self == .blue
    }

    var title: String {
        switch self {
        case .green: "Good"
        case .blue: "Normal"
        case .yellow: "Warning"
        case .orange: "Error"
        case .red: "Critical"
        }
    }

    var color: NSColor {
        switch self {
        case .green: NSColor.systemGreen
        case .blue: NSColor.systemBlue
        case .yellow: NSColor.systemYellow
        case .orange: NSColor.systemOrange
        case .red: NSColor.systemRed
        }
    }
}

struct PingSample: Codable, Identifiable, Equatable {
    var id = UUID()
    let timestamp: Date
    let latencyMs: Double?
    let errorMessage: String?

    var isError: Bool {
        errorMessage != nil || latencyMs == nil
    }
}

struct PingSettings: Codable, Equatable {
    var hosts: [String] = ["1.1.1.1", "8.8.8.8"]
    var backgroundInterval: TimeInterval = 5
    var backgroundTimeout: TimeInterval = 3
    var foregroundInterval: TimeInterval = 1
    var foregroundTimeout: TimeInterval = 1
    var chartWindowSeconds: TimeInterval = 5 * 60

    static let storageKey = "PingStats.settings.v1"

    static func load() -> PingSettings {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let settings = try? JSONDecoder().decode(PingSettings.self, from: data)
        else {
            return PingSettings()
        }
        return settings.normalized()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(normalized()) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func normalized() -> PingSettings {
        var copy = self
        copy.hosts = hosts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        copy.backgroundInterval = max(1, backgroundInterval)
        copy.backgroundTimeout = max(0.2, backgroundTimeout)
        copy.foregroundInterval = max(0.5, foregroundInterval)
        copy.foregroundTimeout = max(0.2, foregroundTimeout)
        copy.chartWindowSeconds = max(60, chartWindowSeconds)
        return copy
    }
}

@MainActor
final class HostMonitor: ObservableObject, Identifiable {
    let id: UUID
    let host: String
    @Published private(set) var samples: [PingSample]
    @Published private(set) var health: PingHealth
    @Published var isPinging = false

    init(id: UUID = UUID(), host: String, samples: [PingSample] = []) {
        self.id = id
        self.host = host
        self.samples = samples
        self.health = Self.evaluate(samples)
    }

    var latestLatencyText: String {
        guard let latency = samples.last?.latencyMs else { return "-" }
        return "\(Int(latency.rounded())) ms"
    }

    var average10Text: String {
        let recent = Array(samples.suffix(10))
        let latencies = recent.compactMap(\.latencyMs)
        guard !latencies.isEmpty else { return "-" }
        let average = latencies.reduce(0, +) / Double(latencies.count)
        return "\(Int(average.rounded())) ms avg"
    }

    func record(_ sample: PingSample, keeping seconds: TimeInterval) -> (old: PingHealth, new: PingHealth) {
        let old = health
        samples.append(sample)
        let cutoff = Date().addingTimeInterval(-seconds)
        samples.removeAll { $0.timestamp < cutoff }
        health = Self.evaluate(samples)
        return (old, health)
    }

    static func evaluate(_ samples: [PingSample]) -> PingHealth {
        let last5 = Array(samples.suffix(5))
        if last5.filter(\.isError).count >= 4 {
            return .red
        }

        let last10 = Array(samples.suffix(10))
        if last10.contains(where: \.isError) {
            return .orange
        }

        guard last10.count >= 10 else {
            return .yellow
        }

        let latencies = last10.compactMap(\.latencyMs)
        guard latencies.count == 10 else {
            return .orange
        }

        let average = latencies.reduce(0, +) / Double(latencies.count)
        if average < 50 {
            return .green
        }
        if average < 100 {
            return .blue
        }
        return .yellow
    }
}
