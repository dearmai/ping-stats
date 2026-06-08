import SwiftUI

struct MonitorView: View {
    @EnvironmentObject private var model: AppModel
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            header

            if model.monitors.isEmpty {
                ContentUnavailableView("No Hosts", systemImage: "network.slash")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(model.monitors) { monitor in
                        HostChartRow(monitor: monitor, windowSeconds: model.settings.chartWindowSeconds)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: 560, height: 420)
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
}

struct HostChartRow: View {
    @ObservedObject var monitor: HostMonitor
    let windowSeconds: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            PingChart(samples: monitor.samples, health: monitor.health, windowSeconds: windowSeconds)
                .frame(height: 48)
        }
        .padding(9)
        .frame(minHeight: 104, maxHeight: 104)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color(nsColor: monitor.health.color))
                    .frame(width: 9, height: 9)

                Text(monitor.host)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

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
            Text("\(Int(windowSeconds / 60)) min")
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
