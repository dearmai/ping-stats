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
- `LaunchAtLogin.swift` — `SMAppService.mainApp` wrapper for the login-item toggle.
- `NetworkInterfaces.swift` — `getifaddrs` sweep behind `LocalAddressProvider.current()`,
  plus the SystemConfiguration BSD-name → "Wi-Fi" display-name lookup.
- `Localization.swift` — `L10n.string(_:)` for non-literal UI strings.
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
shown gray); otherwise by 10-sample average latency — green < the green threshold
(`PingSettings.greenLatencyMs`, default 60 ms), blue < the blue threshold
(`PingSettings.blueLatencyMs`, default 120 ms), else yellow; both are edited in settings.
`isNormal` == green or blue. Thresholds are threaded through `record` → `evaluate`;
a `max(green, blue)` guard keeps blue ≥ green if blue is set below green.

**Notifications** (`AppModel.notifyIfNeeded`): fire on a health-band change, i.e.
normal↔abnormal crossings (including **recovery**) and severity changes among
yellow/orange/red. Warm-up settling into normal (`.unknown` → green/blue) also fires.
Suppressed: moving *into* `.unknown`, `.unknown` → abnormal (a target already down at
launch stays quiet until it recovers), and green↔blue flapping. Recovery from a real
problem (abnormal, non-`.unknown` → normal) sets a distinct "recovered" title.
On top of that, each target carries `notifyLevels: Set<NotifyLevel>` (`.warning` = yellow,
`.error` = orange/red; the settings "All" checkbox just sets both). An abnormal band is
reported only if its level is enabled; a return to normal follows the band being *left*,
and a warm-up settle needs any level enabled.

**Status bar layout** (`StatusBarImageRenderer`): under 10 targets keeps the original
single row (7 px pitch); from 10 it switches to a 2-row grid, 1 px gap both axes,
row-major with the top row first.

**Address modes** (`PingTarget.probeMode` / `ProbeAddress.parse`): `http(s)://` → HTTP
status check (2xx/3xx ok); `host:port` → TCP connect latency; otherwise → ICMP ping.

**Local IP bar** (`LocalAddressProvider` → `AppModel.localAddresses` → `MonitorView`):
`getifaddrs` over every `IFF_UP`, non-loopback interface, skipping link-local
(`169.254.*`, `fe80::`) and `::1`; sorted named-NIC-first, then IPv4 before IPv6.
Refreshed on every tick with an equality guard so the popover only redraws on change.

**Launch at login** (`LaunchAtLogin`): `SMAppService.mainApp` is the source of truth —
never mirrored into `PingSettings`. The settings checkbox applies on toggle, not on Save,
and is disabled unless the executable is inside a `.app` with a bundle id.

**Localization**: the English UI text *is* the key, so SwiftUI `LocalizedStringKey`
literals localize themselves; non-literal sites (enum titles, `String(format:)`, AppKit
window/tooltip strings) go through `L10n.string(_:)`. Translations live in
`Resources/<lang>.lproj/Localizable.strings` and are copied into the bundle by
`scripts/build-app.sh` (with `CFBundleLocalizations`); a missing bundle falls back to
English. New user-facing text means a new key in `Resources/ko.lproj/Localizable.strings`.

**Persistence**: `PingSettings` is JSON in `UserDefaults` under `PingStats.settings.v1`,
with a `LegacyPingSettings` migration path. `.normalized()` clamps intervals/timeouts and
drops empty addresses — call it after any settings mutation (`updateSettings` already does).

## Conventions

- Everything UI/model-facing is `@MainActor`; probes run off-actor and hop back via
  `MainActor.run`.
- Keep the app dependency-free and match the existing terse, comment-light style.
- When changing health bands or notification rules, update the README color/notification
  sections (both `README.md` and `README.ko.md`) to stay truthful.
