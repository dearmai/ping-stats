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

        let view = SettingsView(model: model) { [weak self] in
            self?.window?.close()
        }
        let hostingController = NSHostingController(rootView: view)
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "PingStats Settings"
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.setContentSize(NSSize(width: 560, height: 420))
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    let onSave: () -> Void

    @State private var targets: [EditableTarget]
    @State private var backgroundInterval: Double
    @State private var backgroundTimeout: Double
    @State private var foregroundInterval: Double
    @State private var foregroundTimeout: Double

    init(model: AppModel, onSave: @escaping () -> Void) {
        self.model = model
        self.onSave = onSave
        let settings = model.settings
        _targets = State(initialValue: settings.targets.map(EditableTarget.init))
        _backgroundInterval = State(initialValue: settings.backgroundInterval)
        _backgroundTimeout = State(initialValue: settings.backgroundTimeout)
        _foregroundInterval = State(initialValue: settings.foregroundInterval)
        _foregroundTimeout = State(initialValue: settings.foregroundTimeout)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Targets")
                    .font(.headline)

                Spacer()

                Button {
                    targets.append(EditableTarget(name: "", address: ""))
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add target")
            }

            targetEditor

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
        .frame(width: 560, height: 420)
    }

    private var targetEditor: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .leading)
                Text("Address")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                    .frame(width: 24)
            }

            ForEach($targets) { $target in
                HStack(spacing: 8) {
                    TextField("Name", text: $target.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)

                    TextField("IP or IP:port", text: $target.address)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        targets.removeAll { $0.id == target.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove target")
                }
            }
        }
        .frame(height: 150, alignment: .top)
    }

    private func save() {
        let savedTargets = targets
            .map { PingTarget(id: $0.id, name: $0.name, address: $0.address).normalized }
            .filter { !$0.address.isEmpty }

        model.updateSettings(PingSettings(
            targets: savedTargets,
            backgroundInterval: backgroundInterval,
            backgroundTimeout: backgroundTimeout,
            foregroundInterval: foregroundInterval,
            foregroundTimeout: foregroundTimeout,
            chartWindowSeconds: model.settings.chartWindowSeconds
        ))
        onSave()
    }
}

private struct EditableTarget: Identifiable {
    var id: UUID
    var name: String
    var address: String

    init(id: UUID = UUID(), name: String, address: String) {
        self.id = id
        self.name = name
        self.address = address
    }

    init(_ target: PingTarget) {
        id = target.id
        name = target.name
        address = target.address
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
