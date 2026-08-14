import SwiftUI

struct MonitorView: View {
    @EnvironmentObject private var model: AppModel
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    static let width: CGFloat = 560
    static let minHeight: CGFloat = 220
    static let maxHeight: CGFloat = 640

    private static let headerHeight: CGFloat = 44
    private static let addressBarHeight: CGFloat = 26
    private static let gridPadding: CGFloat = 28
    private static let gridSpacing: CGFloat = 10
    private static let cardHeight: CGFloat = 112

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            addressBar

            if model.monitors.isEmpty {
                ContentUnavailableView("No Hosts", systemImage: "network.slash")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: Self.gridSpacing),
                            GridItem(.flexible(), spacing: Self.gridSpacing)
                        ],
                        alignment: .leading,
                        spacing: Self.gridSpacing
                    ) {
                        ForEach(model.monitors) { monitor in
                            HostChartRow(monitor: monitor, windowSeconds: model.settings.chartWindowSeconds)
                        }
                    }
                    .padding(14)
                }
                .scrollIndicators(.visible)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: Self.width, height: Self.contentHeight(for: model.monitors.count))
    }

    static func contentSize(for monitorCount: Int) -> NSSize {
        NSSize(width: width, height: contentHeight(for: monitorCount))
    }

    private static func contentHeight(for monitorCount: Int) -> CGFloat {
        guard monitorCount > 0 else { return minHeight }

        let rowCount = CGFloat((monitorCount + 1) / 2)
        let spacing = max(0, rowCount - 1) * gridSpacing
        let contentHeight = headerHeight + addressBarHeight + gridPadding
            + (rowCount * cardHeight) + spacing
        return min(max(contentHeight, minHeight), maxHeight)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(Self.clockFormatter.string(from: model.currentTime))
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .frame(width: 92, alignment: .leading)

            Spacer()

            Button(action: { model.pingNow() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Ping now")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")

            Button(action: onQuit) {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var addressBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "network")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if model.localAddresses.isEmpty {
                Text("No local address")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(model.localAddresses) { address in
                            LocalAddressChip(address: address)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .frame(height: Self.addressBarHeight)
        .padding(.horizontal, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct LocalAddressChip: View {
    let address: LocalAddress

    @State private var didCopy = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(address.address, forType: .string)
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                didCopy = false
            }
        } label: {
            HStack(spacing: 4) {
                Text(address.label)
                    .foregroundStyle(.secondary)
                Text(address.address)
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
            }
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(didCopy
            ? L10n.string("Copied")
            : String(format: L10n.string("%@ · %@ — click to copy"), address.interface, address.address))
    }
}

struct HostChartRow: View {
    @ObservedObject var monitor: HostMonitor
    let windowSeconds: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            PingChart(samples: monitor.samples, health: monitor.health, windowSeconds: windowSeconds)
                .frame(height: 42)
        }
        .padding(9)
        .frame(minHeight: 112, maxHeight: 112)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color(nsColor: monitor.health.color))
                    .frame(width: 9, height: 9)

                Text(monitor.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                Text(monitor.probeMode.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .help(monitor.address)

            Text(monitor.address)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(monitor.latestLatencyText)
                    .font(.system(.callout, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 4)

                Text(monitor.average10Text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

struct PingChart: View {
    let samples: [PingSample]
    let health: PingHealth
    let windowSeconds: TimeInterval

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(Path(bounds), with: .color(Color(nsColor: .textBackgroundColor)))

            drawGrid(context: context, size: size)

            let now = Date()
            let start = now.addingTimeInterval(-windowSeconds)
            let visible = samples.filter { $0.timestamp >= start }
            guard !visible.isEmpty else { return }

            let maxLatency = max(250, visible.compactMap(\.latencyMs).max() ?? 250)
            var path = Path()
            var didMove = false

            for sample in visible {
                let elapsed = sample.timestamp.timeIntervalSince(start)
                let x = CGFloat(elapsed / windowSeconds) * size.width
                if let latency = sample.latencyMs {
                    let yRatio = min(latency / maxLatency, 1)
                    let y = size.height - CGFloat(yRatio) * (size.height - 12) - 6
                    let point = CGPoint(x: x, y: y)
                    if didMove {
                        path.addLine(to: point)
                    } else {
                        path.move(to: point)
                        didMove = true
                    }
                } else {
                    let errorRect = CGRect(x: x - 2, y: 8, width: 4, height: size.height - 16)
                    context.fill(Path(roundedRect: errorRect, cornerRadius: 2), with: .color(.red))
                    didMove = false
                }
            }

            context.stroke(path, with: .color(Color(nsColor: health.color)), lineWidth: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .topTrailing) {
            Text(String(format: L10n.string("%d min"), Int(windowSeconds / 60)))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(4)
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        var grid = Path()
        for index in 1..<4 {
            let y = size.height * CGFloat(index) / 4
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(grid, with: .color(Color(nsColor: .separatorColor).opacity(0.5)), lineWidth: 1)
    }
}
