#!/usr/bin/env swift

// make-app-icon.swift ==========================================================
// What it does:
// - Draws the Arturo app icon at every size the asset catalog asks for and
//   writes the PNGs into AppIcon.appiconset.
//
// Design: the app's own mark — three equal photograph panes on the Cinema Veil
// canvas. Muted sky/land gradients per pane so the icon reads as photographs at
// 128 pt and as three clean panes at 16 pt; no text, no chrome, no baked shadow
// (macOS adds the Dock shadow itself).
//
// Requirements:
//   - Xcode 26 command line tools (swift, AppKit, CoreGraphics)
//
// Usage:
//   swift scripts/make-app-icon.swift [output-directory]
//   make icon          # same thing, with the repo's paths

import AppKit
import CoreGraphics
import Foundation

let design: CGFloat = 1024
let outputDirectory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Sources/Resources/Assets.xcassets/AppIcon.appiconset"

/// Every slot the macOS app-icon set needs, and the pixels its file holds.
let slots: [(file: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

struct Pane {
    let skyTop: CGColor
    let skyBottom: CGColor
    let land: CGColor
}

let panes = [
    Pane(
        skyTop: CGColor(red: 0.96, green: 0.79, blue: 0.52, alpha: 1),
        skyBottom: CGColor(red: 0.86, green: 0.60, blue: 0.32, alpha: 1),
        land: CGColor(red: 0.47, green: 0.30, blue: 0.17, alpha: 1)
    ),
    Pane(
        skyTop: CGColor(red: 0.60, green: 0.85, blue: 0.89, alpha: 1),
        skyBottom: CGColor(red: 0.31, green: 0.60, blue: 0.67, alpha: 1),
        land: CGColor(red: 0.14, green: 0.32, blue: 0.38, alpha: 1)
    ),
    Pane(
        skyTop: CGColor(red: 0.95, green: 0.73, blue: 0.68, alpha: 1),
        skyBottom: CGColor(red: 0.80, green: 0.47, blue: 0.49, alpha: 1),
        land: CGColor(red: 0.41, green: 0.22, blue: 0.24, alpha: 1)
    ),
]

func gradient(_ colors: [CGColor]) -> CGGradient {
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: [0, 1]
    ) else {
        fatalError("could not build a gradient")
    }
    return gradient
}

/// The rounded-square body, inset the way macOS app icons are.
func drawBody(in context: CGContext) {
    let body = CGPath(
        roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
        cornerWidth: 188,
        cornerHeight: 188,
        transform: nil
    )
    let top = CGPoint(x: 0, y: 924)
    let bottom = CGPoint(x: 0, y: 100)

    context.saveGState()
    context.addPath(body)
    context.clip()
    context.drawLinearGradient(
        gradient([
            CGColor(red: 0.17, green: 0.18, blue: 0.20, alpha: 1),
            CGColor(red: 0.035, green: 0.035, blue: 0.04, alpha: 1),
        ]),
        start: top,
        end: bottom,
        options: []
    )
    context.restoreGState()

    // Inner edge light: keeps the body from reading as a flat black square.
    context.saveGState()
    context.addPath(body)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    context.setLineWidth(3)
    context.strokePath()
    context.restoreGState()
}

func drawPane(_ pane: Pane, in rect: CGRect, context: CGContext) {
    let frame = CGPath(
        roundedRect: rect,
        cornerWidth: 14,
        cornerHeight: 14,
        transform: nil
    )

    context.saveGState()
    context.addPath(frame)
    context.clip()
    context.drawLinearGradient(
        gradient([pane.skyTop, pane.skyBottom]),
        start: CGPoint(x: 0, y: rect.maxY),
        end: CGPoint(x: 0, y: rect.minY),
        options: []
    )

    // A low horizon band: at 128 pt this is a photograph, at 16 pt it is simply
    // a slightly darker lower half.
    let horizon = rect.minY + rect.height * 0.42
    let land = CGMutablePath()
    land.move(to: CGPoint(x: rect.minX, y: rect.minY))
    land.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    land.addLine(to: CGPoint(x: rect.maxX, y: horizon + rect.height * 0.06))
    land.addLine(to: CGPoint(x: rect.minX, y: horizon - rect.height * 0.04))
    land.closeSubpath()
    context.addPath(land)
    context.setFillColor(pane.land)
    context.fillPath()
    context.restoreGState()

    // Hairline around each pane, as the app draws around a tile.
    context.saveGState()
    context.addPath(frame)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    context.setLineWidth(2.5)
    context.strokePath()
    context.restoreGState()
}

/// Three equal panes, matching the viewer's columns.
func drawPanes(in context: CGContext) {
    let paneWidth: CGFloat = 188
    let paneHeight: CGFloat = 300
    let gap: CGFloat = 18
    let totalWidth = paneWidth * 3 + gap * 2
    let startX = (design - totalWidth) / 2
    let originY = (design - paneHeight) / 2

    for (index, pane) in panes.enumerated() {
        let rect = CGRect(
            x: startX + CGFloat(index) * (paneWidth + gap),
            y: originY,
            width: paneWidth,
            height: paneHeight
        )
        drawPane(pane, in: rect, context: context)
    }
}

func drawIcon(in context: CGContext, pixels: Int) {
    context.scaleBy(x: CGFloat(pixels) / design, y: CGFloat(pixels) / design)
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)

    drawBody(in: context)
    drawPanes(in: context)
}

func pngBytes(pixels: Int) -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("could not allocate a \(pixels)px bitmap")
    }

    guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("could not create a graphics context")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    drawIcon(in: graphics.cgContext, pixels: pixels)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("could not encode a \(pixels)px PNG")
    }
    return data
}

let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

for slot in slots {
    let url = directory.appending(path: slot.file)
    try pngBytes(pixels: slot.pixels).write(to: url)
    print("wrote \(slot.file) (\(slot.pixels)×\(slot.pixels))")
}

print("done: \(slots.count) files in \(directory.path)")
