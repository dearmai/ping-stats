import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate()
            return
        }

        let view = SettingsView(model: model)
        let hostingController = NSHostingController(rootView: view)
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "PingStats Settings"
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.setContentSize(NSSize(width: 420, height: 380))
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    @State private var hostsText: String
    @State private var backgroundInterval: Double
    @State private var backgroundTimeout: Double
    @State private var foregroundInterval: Double
    @State private var foregroundTimeout: Double

    init(model: AppModel) {
        self.model = model
        let settings = model.settings
        _hostsText = State(initialValue: settings.hosts.joined(separator: "\n"))
        _backgroundInterval = State(initialValue: settings.backgroundInterval)
        _backgroundTimeout = State(initialValue: settings.backgroundTimeout)
        _foregroundInterval = State(initialValue: settings.foregroundInterval)
        _foregroundTimeout = State(initialValue: settings.foregroundTimeout)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hosts")
                .font(.headline)

            TextEditor(text: $hostsText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 128)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Background")
                    NumberField(title: "Interval", value: $backgroundInterval, suffix: "sec")
                    NumberField(title: "Timeout", value: $backgroundTimeout, suffix: "sec")
                }

                GridRow {
                    Text("Foreground")
                    NumberField(title: "Interval", value: $foregroundInterval, suffix: "sec")
                    NumberField(title: "Timeout", value: $foregroundTimeout, suffix: "sec")
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 420, height: 380)
    }

    private func save() {
        let hosts = hostsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        model.updateSettings(PingSettings(
            hosts: hosts,
            backgroundInterval: backgroundInterval,
            backgroundTimeout: backgroundTimeout,
            foregroundInterval: foregroundInterval,
            foregroundTimeout: foregroundTimeout,
            chartWindowSeconds: model.settings.chartWindowSeconds
        ))
    }
}

struct NumberField: View {
    let title: String
    @Binding var value: Double
    let suffix: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            TextField(title, value: $value, format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 54)
            Text(suffix)
                .foregroundStyle(.secondary)
        }
    }
}
