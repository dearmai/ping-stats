import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
        newWindow.title = L10n.string("PingStats Settings")
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.setContentSize(NSSize(width: 660, height: 440))
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
    @State private var chartWindowMinutes: Double
    @State private var greenLatencyMs: Double
    @State private var blueLatencyMs: Double
    @State private var launchAtLogin: Bool
    @State private var launchAtLoginError: String?
    @State private var draggingTargetID: UUID?

    init(model: AppModel, onSave: @escaping () -> Void) {
        self.model = model
        self.onSave = onSave
        let settings = model.settings
        _targets = State(initialValue: settings.targets.map(EditableTarget.init))
        _backgroundInterval = State(initialValue: settings.backgroundInterval)
        _backgroundTimeout = State(initialValue: settings.backgroundTimeout)
        _foregroundInterval = State(initialValue: settings.foregroundInterval)
        _foregroundTimeout = State(initialValue: settings.foregroundTimeout)
        _chartWindowMinutes = State(initialValue: settings.chartWindowSeconds / 60)
        _greenLatencyMs = State(initialValue: settings.greenLatencyMs)
        _blueLatencyMs = State(initialValue: settings.blueLatencyMs)
        _launchAtLogin = State(initialValue: LaunchAtLogin.isEnabled)
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

                GridRow {
                    Text("Chart")
                    NumberField(title: "Window", value: $chartWindowMinutes, suffix: "min")
                    Text("1-60 min")
                        .foregroundStyle(.secondary)
                }

                GridRow {
                    Text("Health")
                    NumberField(title: "Green \u{2264}", value: $greenLatencyMs, suffix: "ms")
                    NumberField(title: "Blue \u{2264}", value: $blueLatencyMs, suffix: "ms")
                }

                GridRow {
                    Text("Startup")
                    // Login-item registration is system state, so it applies on toggle
                    // rather than waiting for Save.
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .toggleStyle(.checkbox)
                        .disabled(!LaunchAtLogin.isSupported)
                        .onChange(of: launchAtLogin) { _, isOn in
                            applyLaunchAtLogin(isOn)
                        }
                    launchAtLoginStatus
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
        .frame(width: 660, height: 440)
    }

    private var targetEditor: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Color.clear
                    .frame(width: 16)
                Text("Use")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)
                Text("Address")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Notify")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 180, alignment: .leading)
                Spacer()
                    .frame(width: 24)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach($targets) { $target in
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(width: 16)
                                .contentShape(Rectangle())
                                .onDrag {
                                    draggingTargetID = target.id
                                    return NSItemProvider(object: target.id.uuidString as NSString)
                                }
                                .help("Drag to reorder")

                            Toggle("", isOn: $target.isEnabled)
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                .frame(width: 34, alignment: .leading)
                                .help("Enable target")

                            TextField("Name", text: $target.name)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 130)

                            TextField("IP, IP:port, or URL", text: $target.address)
                                .textFieldStyle(.roundedBorder)

                            NotifyLevelToggles(target: $target)
                                .frame(width: 180, alignment: .leading)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: TargetDropDelegate(
                                targetID: target.id,
                                targets: $targets,
                                draggingTargetID: $draggingTargetID
                            )
                        )
                    }
                }
                .padding(.trailing, 4)
            }
            .scrollIndicators(.visible)
            .frame(height: 150)
        }
    }

    @ViewBuilder
    private var launchAtLoginStatus: some View {
        if let launchAtLoginError {
            Text(launchAtLoginError)
                .font(.caption)
                .foregroundStyle(Color.red)
                .lineLimit(2)
        } else if !LaunchAtLogin.isSupported {
            Text("Needs the PingStats.app bundle")
                .font(.caption)
                .foregroundStyle(Color.secondary)
        } else if LaunchAtLogin.requiresApproval {
            HStack(spacing: 6) {
                Text("Approval needed")
                    .foregroundStyle(Color.secondary)
                Button("Open Login Items") {
                    LaunchAtLogin.openLoginItemsSettings()
                }
            }
            .font(.caption)
        } else {
            Color.clear.frame(height: 1)
        }
    }

    private func applyLaunchAtLogin(_ isOn: Bool) {
        do {
            try LaunchAtLogin.setEnabled(isOn)
            launchAtLoginError = nil
        } catch {
            launchAtLogin = LaunchAtLogin.isEnabled
            launchAtLoginError = error.localizedDescription
        }
    }

    private func save() {
        let savedTargets = targets
            .map {
                PingTarget(
                    id: $0.id,
                    name: $0.name,
                    address: $0.address,
                    isEnabled: $0.isEnabled,
                    notifyLevels: $0.notifyLevels
                )
                .normalized
            }
            .filter { !$0.address.isEmpty }

        model.updateSettings(PingSettings(
            targets: savedTargets,
            backgroundInterval: backgroundInterval,
            backgroundTimeout: backgroundTimeout,
            foregroundInterval: foregroundInterval,
            foregroundTimeout: foregroundTimeout,
            chartWindowSeconds: chartWindowMinutes * 60,
            greenLatencyMs: greenLatencyMs,
            blueLatencyMs: blueLatencyMs
        ))
        onSave()
    }
}

private struct EditableTarget: Identifiable {
    var id: UUID
    var name: String
    var address: String
    var isEnabled: Bool
    var notifyLevels: Set<NotifyLevel>

    init(
        id: UUID = UUID(),
        name: String,
        address: String,
        isEnabled: Bool = true,
        notifyLevels: Set<NotifyLevel> = [.warning, .error]
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.isEnabled = isEnabled
        self.notifyLevels = notifyLevels
    }

    init(_ target: PingTarget) {
        id = target.id
        name = target.name
        address = target.address
        isEnabled = target.isEnabled
        notifyLevels = target.notifyLevels
    }
}

private struct NotifyLevelToggles: View {
    @Binding var target: EditableTarget

    var body: some View {
        HStack(spacing: 8) {
            toggle("Warning", level: .warning)
            toggle("Error", level: .error)
            Toggle("All", isOn: Binding(
                get: { NotifyLevel.allCases.allSatisfy(target.notifyLevels.contains) },
                set: { isOn in
                    target.notifyLevels = isOn ? Set(NotifyLevel.allCases) : []
                }
            ))
            .help("Enable every level")
        }
        .toggleStyle(.checkbox)
        .font(.caption)
    }

    private func toggle(_ title: LocalizedStringKey, level: NotifyLevel) -> some View {
        Toggle(title, isOn: Binding(
            get: { target.notifyLevels.contains(level) },
            set: { isOn in
                if isOn {
                    target.notifyLevels.insert(level)
                } else {
                    target.notifyLevels.remove(level)
                }
            }
        ))
    }
}

private struct TargetDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var targets: [EditableTarget]
    @Binding var draggingTargetID: UUID?

    func dropEntered(info: DropInfo) {
        guard
            let draggingTargetID,
            draggingTargetID != targetID,
            let sourceIndex = targets.firstIndex(where: { $0.id == draggingTargetID }),
            let destinationIndex = targets.firstIndex(where: { $0.id == targetID })
        else {
            return
        }

        withAnimation(.default) {
            targets.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingTargetID = nil
        return true
    }
}

struct NumberField: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let suffix: LocalizedStringKey

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
