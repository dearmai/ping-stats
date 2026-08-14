import Foundation
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var settings: PingSettings
    @Published private(set) var monitors: [HostMonitor]
    @Published private(set) var currentTime = Date()
    @Published private(set) var isForeground = false
    @Published private(set) var localAddresses: [LocalAddress] = []

    private var timer: Timer?

    init() {
        let loadedSettings = PingSettings.load()
        settings = loadedSettings
        monitors = loadedSettings.targets
            .filter(\.isEnabled)
            .map { HostMonitor(target: $0) }
    }

    func start() {
        refreshLocalAddresses()
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
        refreshLocalAddresses()
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
                    let transition = monitor.record(
                        sample,
                        keeping: settings.chartWindowSeconds,
                        greenThresholdMs: settings.greenLatencyMs,
                        blueThresholdMs: settings.blueLatencyMs
                    )
                    monitor.isPinging = false
                    notifyIfNeeded(target: monitor.target, old: transition.old, new: transition.new)
                }
            }
        }
    }

    /// Cheap enough to run on every tick; the equality guard keeps the popover
    /// from redrawing while the NIC list is unchanged.
    private func refreshLocalAddresses() {
        let next = LocalAddressProvider.current()
        guard next != localAddresses else { return }
        localAddresses = next
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

    private func notifyIfNeeded(target: PingTarget, old: PingHealth, new: PingHealth) {
        // Alert on any band change except:
        //  - moving INTO .unknown (samples aged out / warming up again)
        //  - green <-> blue flapping (both normal, low signal)
        //  - .unknown -> abnormal (a target already down at launch stays quiet;
        //    only its later recovery is reported)
        // Warm-up settling into normal (.unknown -> green/blue) DOES notify.
        let shouldNotify = old != new
            && new != .unknown
            && (old != .unknown || new.isNormal)
            && !(old.isNormal && new.isNormal)
        guard shouldNotify else { return }

        // Per-target level filter: an abnormal band notifies only when its level is
        // enabled; returning to normal follows the band being left, and a warm-up
        // settle (no band to follow) needs at least one level enabled.
        let allowedByTarget = new.isNormal
            ? (old == .unknown ? !target.notifyLevels.isEmpty : target.notifies(old))
            : target.notifies(new)
        guard allowedByTarget else { return }

        let host = target.title
        let recovered = old != .unknown && !old.isNormal && new.isNormal
        let content = UNMutableNotificationContent()
        content.title = String(
            format: recovered ? L10n.string("PingStats: %@ recovered") : L10n.string("PingStats: %@"),
            host
        )
        content.body = String(format: L10n.string("%@ → %@"), old.title, new.title)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(host)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
