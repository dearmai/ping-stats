import Foundation
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var settings: PingSettings
    @Published private(set) var monitors: [HostMonitor]
    @Published private(set) var currentTime = Date()
    @Published private(set) var isForeground = false

    private var timer: Timer?

    init() {
        let loadedSettings = PingSettings.load()
        settings = loadedSettings
        monitors = loadedSettings.targets
            .filter(\.isEnabled)
            .map { HostMonitor(target: $0) }
    }

    func start() {
        rescheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setForeground(_ foreground: Bool) {
        guard isForeground != foreground else { return }
        isForeground = foreground
        rescheduleTimer()
    }

    func updateSettings(_ next: PingSettings) {
        let normalized = next.normalized()
        settings = normalized
        settings.save()
        reconcileTargets(normalized.targets.filter(\.isEnabled))
        rescheduleTimer()
    }

    func pingNow() {
        currentTime = Date()
        let timeout = isForeground ? settings.foregroundTimeout : settings.backgroundTimeout
        for monitor in monitors where !monitor.isPinging {
            monitor.isPinging = true
            Task {
                let result = await PingService.probe(address: monitor.address, timeout: timeout)
                await MainActor.run {
                    let sample = PingSample(
                        timestamp: Date(),
                        latencyMs: result.latencyMs,
                        errorMessage: result.errorMessage
                    )
                    let transition = monitor.record(sample, keeping: settings.chartWindowSeconds)
                    monitor.isPinging = false
                    notifyIfNeeded(host: monitor.title, old: transition.old, new: transition.new)
                }
            }
        }
    }

    private func reconcileTargets(_ targets: [PingTarget]) {
        var existing: [String: HostMonitor] = [:]
        for monitor in monitors {
            existing[monitor.address] = monitor
        }

        monitors = targets.map { target in
            if let monitor = existing[target.address] {
                monitor.updateTarget(target)
                return monitor
            }
            return HostMonitor(target: target)
        }
    }

    private func rescheduleTimer() {
        timer?.invalidate()
        let interval = isForeground ? settings.foregroundInterval : settings.backgroundInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pingNow()
            }
        }
        pingNow()
    }

    private func notifyIfNeeded(host: String, old: PingHealth, new: PingHealth) {
        let shouldNotify = (old.isNormal && !new.isNormal) || (!old.isNormal && !new.isNormal && old != new)
        guard shouldNotify else { return }

        let content = UNMutableNotificationContent()
        content.title = "PingStats: \(host)"
        content.body = "\(old.title) -> \(new.title)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(host)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
