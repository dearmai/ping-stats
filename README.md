# PingStats

macOS menu bar app that periodically pings configured hosts and shows their health as vertical colored bars in the menu bar.

[한국어 README](README.ko.md)

## Features

- Multiple named target configuration from a settings window.
- Address mode:
  - `IP` runs normal ping.
  - `IP:port` runs TCP connect latency checks.
- Background ping loop, default interval 5 seconds and timeout 3 seconds.
- Foreground ping loop while the popover is open, default interval 1 second and timeout 1 second.
- Menu bar color per host:
  - Green: recent 10-sample average under the configurable green threshold (default 60 ms), editable in settings.
  - Blue: recent 10-sample average under the configurable blue threshold (default 120 ms), editable in settings.
  - Yellow: recent 10-sample average at or above the blue threshold.
  - Orange: at least one timeout or network error in the recent 10 samples.
  - Red: at least 4 errors in the recent 5 samples.
  - Gray: warming up, fewer than 10 samples and no errors yet.
- User notification rules:
  - Any health-band change: normal (green/blue) to a warning/error state, and recovery back to normal.
  - Any severity change among yellow, orange, and red.
  - Warm-up settling into normal (gray to green/blue) is reported once monitoring stabilizes.
  - No notification for green to blue or blue to green, for moving back into the warming-up gray state, or for a target that is already down at launch (gray straight to an error state); only its later recovery is reported.
- Popover chart with current `HH:mm:ss` time and recent 5-minute response history.

## Build

This project is intentionally dependency-free and uses Swift Package Manager:

```sh
swift build
swift run PingStats
```

To create a menu bar `.app` bundle:

```sh
chmod +x scripts/build-app.sh
scripts/build-app.sh
open build/PingStats.app
```

To sign the app with a local self-signed code signing certificate and create a zip package:

```sh
scripts/sign-self-signed.sh
```

If the self-signed identity is not trusted yet, run the script with explicit local trust:

```sh
scripts/sign-self-signed.sh --trust-local
```

The signing script creates `dist/PingStats.zip` and exports `dist/PingStatsSelfSigned.cer`. On another Mac, the certificate is not trusted automatically; use Control-click > Open for first launch, or import the exported certificate into Keychain Access and mark it trusted for code signing.

The GitHub Actions workflow uses ad-hoc signing for CI release packages because self-signed certificate trust changes require interactive keychain authorization on macOS.

If `swift build` fails with an SDK/compiler mismatch, install or select a matching Xcode toolchain:

```sh
xcode-select --install
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

After installing Xcode, this helper performs the toolchain switch and verifies the project:

```sh
scripts/verify-xcode-toolchain.sh
```

The current implementation uses AppKit for the status item and SwiftUI for the popover/settings views.
