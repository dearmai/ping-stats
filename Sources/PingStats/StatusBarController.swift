import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    var onOpenSettings: (() -> Void)?

    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var modelCancellables = Set<AnyCancellable>()
    private var monitorCancellables = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let content = MonitorView(
            onOpenSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
        .environmentObject(model)

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 560, height: 420)
        popover.contentViewController = NSHostingController(rootView: content)
        popover.delegate = self

        model.$monitors.sink { [weak self] monitors in
            self?.observe(monitors)
            self?.refreshStatusItem()
        }
        .store(in: &modelCancellables)

        observe(model.monitors)
        refreshStatusItem()
    }

    private func observe(_ monitors: [HostMonitor]) {
        monitorCancellables.removeAll()
        for monitor in monitors {
            monitor.$health.sink { [weak self] _ in
                self?.refreshStatusItem()
            }
            .store(in: &monitorCancellables)

            monitor.$samples.sink { [weak self] _ in
                self?.refreshStatusItem()
            }
            .store(in: &monitorCancellables)
        }
    }

    private func refreshStatusItem() {
        let image = StatusBarImageRenderer.image(for: model.monitors.map(\.health))
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = model.monitors.map {
            "\($0.host): \($0.latestLatencyText) (\($0.health.title))"
        }.joined(separator: "\n")
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
            model.setForeground(false)
        } else {
            model.setForeground(true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func openSettings() {
        popover.performClose(nil)
        model.setForeground(false)
        onOpenSettings?()
    }
}

extension StatusBarController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        model.setForeground(false)
    }
}

enum StatusBarImageRenderer {
    static func image(for statuses: [PingHealth]) -> NSImage {
        let barCount = max(statuses.count, 1)
        let width = CGFloat(barCount * 7 + 4)
        let height: CGFloat = 18
        let image = NSImage(size: NSSize(width: width, height: height))

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        if statuses.isEmpty {
            NSColor.secondaryLabelColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 3, y: 4, width: 4, height: 10), xRadius: 2, yRadius: 2).fill()
        } else {
            for (index, status) in statuses.enumerated() {
                status.color.setFill()
                let x = CGFloat(index * 7 + 3)
                let rect = NSRect(x: x, y: 2, width: 4, height: 14)
                NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            }
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
