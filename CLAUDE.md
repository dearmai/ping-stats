# CLAUDE.md

Guidance for working in this repository.

## Overview

PingStats is a dependency-free macOS **menu bar** app (`LSUIElement`) that periodically
probes configured targets and renders each target's health as a vertical colored bar in
the status item. Built with Swift Package Manager; AppKit for the status item, SwiftUI for
the popover and settings window.

- Minimum target: macOS 14.
- No third-party dependencies. Do not add any without a strong reason.

## Build & run

```sh
swift build                 # debug build
swift run PingStats          # run from CLI
scripts/build-app.sh         # produce build/PingStats.app bundle (release + Info.plist)
scripts/sign-self-signed.sh  # self-sign + package dist/PingStats.zip
```

Notifications require a real `.app` bundle with a bundle id (`dev.pingstats.app`) — they do
**not** appear under bare `swift run`. Test notification behavior via `scripts/build-app.sh`
then `open build/PingStats.app`.

If `swift build` fails on an SDK/toolchain mismatch, run `scripts/verify-xcode-toolchain.sh`.

## Architecture

All source under `Sources/PingStats/`:

- `PingStatsMain.swift` — `@main` entry, wires `AppDelegate`.
- `AppDelegate.swift` — app lifecycle; requests notification authorization, sets the
  `UNUserNotificationCenterDelegate` (so banners show while the app is active), owns
  `AppModel` + controllers.
- `AppModel.swift` — `@MainActor` `ObservableObject`, the core loop. Holds `settings` and
  `[HostMonitor]`, drives the `Timer`, runs probes via `PingService`, records samples, and
  fires notifications (`notifyIfNeeded`). Switches between background/foreground intervals
  via `setForeground`.
- `Models.swift` — domain types: `PingHealth`, `PingSample`, `PingTarget`, `ProbeMode`,
  `PingSettings` (persistence + normalization), and `HostMonitor` (per-target sample buffer
  + health evaluation).
- `PingService.swift` — stateless probe engine. `ProbeAddress.parse` routes an address to
  HTTP (`http(s)://…`), TCP connect (`host:port`), or ICMP (`/sbin/ping` subprocess).
  `PingContinuationBox` guards against double-resume of the continuation.
- `StatusBarController.swift` — status item, popover, and the `StatusBarImageRenderer` that
  draws the colored bars. Observes each monitor's `$health`/`$samples`.
- `MonitorView.swift` — SwiftUI popover content + latency chart (`PingChart`).
- `SettingsWindowController.swift` — target/interval editing UI.

## Domain logic to know

**Health evaluation** (`HostMonitor.evaluate`, recent samples): red = ≥4 errors in last 5;
orange = any error in last 10; `.unknown` = fewer than 10 samples and no errors (warm-up,
shown gray); otherwise by 10-sample average latency — green < 50 ms, blue < the configurable
blue threshold (`PingSettings.blueLatencyMs`, default 60 ms, edited in settings), else
yellow. `isNormal` == green or blue. The threshold is threaded through `record` →
`evaluate`; a `min(50, blue)` guard keeps green ≤ blue if blue is set very low.

**Notifications** (`AppModel.notifyIfNeeded`): fire on a health-band change, i.e.
normal↔abnormal crossings (including **recovery**) and severity changes among
yellow/orange/red. Warm-up settling into normal (`.unknown` → green/blue) also fires.
Suppressed: moving *into* `.unknown`, `.unknown` → abnormal (a target already down at
launch stays quiet until it recovers), and green↔blue flapping. Recovery from a real
problem (abnormal, non-`.unknown` → normal) sets a distinct "recovered" title.

**Address modes** (`PingTarget.probeMode` / `ProbeAddress.parse`): `http(s)://` → HTTP
status check (2xx/3xx ok); `host:port` → TCP connect latency; otherwise → ICMP ping.

**Persistence**: `PingSettings` is JSON in `UserDefaults` under `PingStats.settings.v1`,
with a `LegacyPingSettings` migration path. `.normalized()` clamps intervals/timeouts and
drops empty addresses — call it after any settings mutation (`updateSettings` already does).

## Conventions

- Everything UI/model-facing is `@MainActor`; probes run off-actor and hop back via
  `MainActor.run`.
- Keep the app dependency-free and match the existing terse, comment-light style.
- When changing health bands or notification rules, update the README color/notification
  sections (both `README.md` and `README.ko.md`) to stay truthful.
