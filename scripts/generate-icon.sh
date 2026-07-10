#!/usr/bin/env bash
set -euo pipefail

# Renders the app icon (dark rounded square with the five health-color bars that
# mirror the menu-bar rendering) into Resources/AppIcon.icns.
# Requires: swift, iconutil (both ship with the macOS toolchain).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES_DIR="$ROOT_DIR/Resources"
WORK_DIR="$(mktemp -d)"
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR" "$RES_DIR"

swift - "$ICONSET_DIR" <<'SWIFT'
import AppKit

let outDir = CommandLine.arguments[1]

func color(_ r: Double, _ g: Double, _ b: Double) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

// Five health colors, mirroring PingHealth.color (green/blue/yellow/orange/red).
let barColors = [
    color(52, 199, 89),
    color(0, 122, 255),
    color(255, 204, 0),
    color(255, 149, 0),
    color(255, 59, 48)
]
let barHeights: [CGFloat] = [0.40, 0.56, 0.72, 1.00, 0.84]

func renderPNG(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let S = CGFloat(size)
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: S, height: S).fill()

    let inset = S * 0.09
    let bg = NSRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
    let radius = bg.width * 0.2237
    let bgPath = NSBezierPath(roundedRect: bg, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(
        starting: color(28, 41, 71),
        ending: color(13, 20, 38)
    )!
    gradient.draw(in: bgPath, angle: -90)

    let n = barColors.count
    let gapFrac: CGFloat = 0.55
    let plotInsetX = bg.width * 0.17
    let plotW = bg.width - 2 * plotInsetX
    let barW = plotW / (CGFloat(n) + CGFloat(n - 1) * gapFrac)
    let baseY = bg.minY + bg.height * 0.22
    let maxH = bg.height * 0.56

    for i in 0..<n {
        let x = bg.minX + plotInsetX + CGFloat(i) * (barW * (1 + gapFrac))
        let h = maxH * barHeights[i]
        let rect = NSRect(x: x, y: baseY, width: barW, height: h)
        let path = NSBezierPath(roundedRect: rect, xRadius: barW * 0.32, yRadius: barW * 0.32)
        barColors[i].setFill()
        path.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// name -> pixel size for the .iconset
let entries: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for (name, size) in entries {
    let data = renderPNG(size: size)
    try! data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
SWIFT

iconutil -c icns "$ICONSET_DIR" -o "$RES_DIR/AppIcon.icns"
rm -rf "$WORK_DIR"
echo "$RES_DIR/AppIcon.icns"
