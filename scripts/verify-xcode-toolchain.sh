#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

if [[ ! -d "$XCODE_DEVELOPER_DIR" ]]; then
  cat >&2 <<'EOF'
Xcode is not installed at /Applications/Xcode.app.

Install Xcode from the Mac App Store or Apple Developer downloads, then run:

  scripts/verify-xcode-toolchain.sh
EOF
  exit 1
fi

if [[ "$(xcode-select -p)" != "$XCODE_DEVELOPER_DIR" ]]; then
  echo "Switching xcode-select to $XCODE_DEVELOPER_DIR"
  sudo xcode-select -s "$XCODE_DEVELOPER_DIR"
fi

if xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode command line tools are available"
else
  echo "Accepting Xcode license if required"
  sudo xcodebuild -license accept

  echo "Running Xcode first-launch setup"
  sudo xcodebuild -runFirstLaunch
fi

echo "Developer directory:"
xcode-select -p

echo "Swift version:"
swift --version

cd "$PROJECT_DIR"

echo "Checking SwiftPM manifest"
swift package dump-package > /tmp/ping-stats-package.json

echo "Building PingStats"
swift build

echo "Building app bundle"
scripts/build-app.sh

echo "OK: build/PingStats.app"
