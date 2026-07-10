import AppKit
import Foundation

enum PingHealth: Int, Codable, CaseIterable {
    case green
    case blue
    case yellow
    case orange
    case red
    case unknown

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
        case .unknown: "Unknown"
        }
    }

    var color: NSColor {
        switch self {
        case .green: NSColor.systemGreen
        case .blue: NSColor.systemBlue
        case .yellow: NSColor.systemYellow
        case .orange: NSColor.systemOrange
        case .red: NSColor.systemRed
        case .unknown: NSColor.systemGray
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

struct PingTarget: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var address: String
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String = "", address: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.address = address
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case address
        case isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    var title: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? address : trimmedName
    }

    var subtitle: String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : address
    }

    var probeMode: ProbeMode {
        let lowercasedAddress = address.lowercased()
        if lowercasedAddress.hasPrefix("http://") || lowercasedAddress.hasPrefix("https://") {
            return .http
        }
        return address.contains(":") ? .tcping : .ping
    }

    var normalized: PingTarget {
        PingTarget(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            address: address.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: isEnabled
        )
    }
}

enum ProbeMode: String, Codable {
    case ping
    case tcping
    case http

    var title: String {
        rawValue.uppercased()
    }
}

struct PingSettings: Codable, Equatable {
    var targets: [PingTarget] = [
        PingTarget(name: "Cloudflare", address: "1.1.1.1"),
        PingTarget(name: "Google DNS", address: "8.8.8.8")
    ]
    var backgroundInterval: TimeInterval = 5
    var backgroundTimeout: TimeInterval = 3
    var foregroundInterval: TimeInterval = 1
    var foregroundTimeout: TimeInterval = 1
    var chartWindowSeconds: TimeInterval = 10 * 60

    static let storageKey = "PingStats.settings.v1"

    static func load() -> PingSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return PingSettings()
        }

        if let settings = try? JSONDecoder().decode(PingSettings.self, from: data) {
            return settings.normalized()
        }

        if let legacySettings = try? JSONDecoder().decode(LegacyPingSettings.self, from: data) {
            return PingSettings(
                targets: legacySettings.hosts.map { PingTarget(address: $0) },
                backgroundInterval: legacySettings.backgroundInterval,
                backgroundTimeout: legacySettings.backgroundTimeout,
                foregroundInterval: legacySettings.foregroundInterval,
                foregroundTimeout: legacySettings.foregroundTimeout,
                chartWindowSeconds: legacySettings.chartWindowSeconds
            )
            .normalized()
        }

        return PingSettings()
    }

    private struct LegacyPingSettings: Codable {
        var hosts: [String]
        var backgroundInterval: TimeInterval
        var backgroundTimeout: TimeInterval
        var foregroundInterval: TimeInterval
        var foregroundTimeout: TimeInterval
        var chartWindowSeconds: TimeInterval
    }

    init(
        targets: [PingTarget] = [
            PingTarget(name: "Cloudflare", address: "1.1.1.1"),
            PingTarget(name: "Google DNS", address: "8.8.8.8")
        ],
        backgroundInterval: TimeInterval = 5,
        backgroundTimeout: TimeInterval = 3,
        foregroundInterval: TimeInterval = 1,
        foregroundTimeout: TimeInterval = 1,
        chartWindowSeconds: TimeInterval = 10 * 60
    ) {
        self.targets = targets
        self.backgroundInterval = backgroundInterval
        self.backgroundTimeout = backgroundTimeout
        self.foregroundInterval = foregroundInterval
        self.foregroundTimeout = foregroundTimeout
        self.chartWindowSeconds = chartWindowSeconds
    }

    func save() {
        guard let data = try? JSONEncoder().encode(normalized()) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func normalized() -> PingSettings {
        var copy = self
        copy.targets = targets
            .map(\.normalized)
            .filter { !$0.address.isEmpty }
        copy.backgroundInterval = max(1, backgroundInterval)
        copy.backgroundTimeout = max(0.2, backgroundTimeout)
        copy.foregroundInterval = max(0.5, foregroundInterval)
        copy.foregroundTimeout = max(0.2, foregroundTimeout)
        copy.chartWindowSeconds = min(max(60, chartWindowSeconds), 60 * 60)
        return copy
    }
}

@MainActor
final class HostMonitor: ObservableObject, Identifiable {
    let id: UUID
    @Published private(set) var target: PingTarget
    @Published private(set) var samples: [PingSample]
    @Published private(set) var health: PingHealth
    @Published var isPinging = false

    init(id: UUID = UUID(), target: PingTarget, samples: [PingSample] = []) {
        self.id = id
        self.target = target
        self.samples = samples
        self.health = Self.evaluate(samples)
    }

    var title: String {
        target.title
    }

    var address: String {
        target.address
    }

    var subtitle: String? {
        target.subtitle
    }

    var probeMode: ProbeMode {
        target.probeMode
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

    func updateTarget(_ next: PingTarget) {
        target = next
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
            return .unknown
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
