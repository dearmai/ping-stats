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
        popover.contentSize = MonitorView.contentSize(for: model.monitors.count)
        popover.contentViewController = NSHostingController(rootView: content)
        popover.delegate = self

        model.$monitors.sink { [weak self] monitors in
            self?.observe(monitors)
            self?.popover.contentSize = MonitorView.contentSize(for: monitors.count)
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
            "\($0.title) [\($0.address)]: \($0.latestLatencyText) (\($0.health.title))"
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
    /// From this many targets the bars wrap into a 2-row grid so the status item
    /// stops eating the menu bar.
    private static let gridThreshold = 10
    private static let barWidth: CGFloat = 4
    private static let gridGap: CGFloat = 1
    private static let horizontalPadding: CGFloat = 3
    private static let imageHeight: CGFloat = 18

    static func image(for statuses: [PingHealth]) -> NSImage {
        guard statuses.count >= gridThreshold else {
            return singleRowImage(for: statuses)
        }
        return gridImage(for: statuses)
    }

    private static func singleRowImage(for statuses: [PingHealth]) -> NSImage {
        let barCount = max(statuses.count, 1)
        let width = CGFloat(barCount * 7 + 4)
        let image = NSImage(size: NSSize(width: width, height: imageHeight))

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        if statuses.isEmpty {
            NSColor.secondaryLabelColor.setFill()
            fill(NSRect(x: 3, y: 4, width: barWidth, height: 10))
        } else {
            for (index, status) in statuses.enumerated() {
                status.color.setFill()
                let x = CGFloat(index * 7 + 3)
                fill(NSRect(x: x, y: 2, width: barWidth, height: 14))
            }
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func gridImage(for statuses: [PingHealth]) -> NSImage {
        // Row-major: first half fills the top row, the rest the bottom row.
        let columns = (statuses.count + 1) / 2
        let pitch = barWidth + gridGap
        let barHeight: CGFloat = 7
        let width = horizontalPadding * 2 + CGFloat(columns) * barWidth + CGFloat(columns - 1) * gridGap
        let image = NSImage(size: NSSize(width: width, height: imageHeight))

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        for (index, status) in statuses.enumerated() {
            status.color.setFill()
            let row = index / columns
            let column = index % columns
            let x = horizontalPadding + CGFloat(column) * pitch
            let y = row == 0 ? 2 + barHeight + gridGap : 2
            fill(NSRect(x: x, y: y, width: barWidth, height: barHeight))
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func fill(_ rect: NSRect) {
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
    }
}
