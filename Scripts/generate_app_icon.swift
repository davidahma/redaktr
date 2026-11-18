#!/usr/bin/env swift

// Generates the Redaktr macOS app icon ("Redacted line" concept) at every size
// the asset catalog needs, writing PNGs straight into AppIcon.appiconset.
//
// This script is the source of truth for the icon. Re-run it after changing the
// design; do not hand-edit the generated PNGs.
//
//     swift Scripts/generate_app_icon.swift
//
// Design: a deep-graphite macOS squircle holding faint "text" lines with one
// opaque black redaction bar snapped over a single line, plus a small green
// "cleared" check. Detail is dropped progressively at small sizes so the bar
// stays unmistakable in the Finder/Dock.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette

func srgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

let backgroundColor = srgb(34, 40, 49)        // #222831 deep graphite
let edgeHighlight = srgb(255, 255, 255, 0.06)
let faintLineColor = srgb(201, 205, 212, 0.5) // #C9CDD4
let barColor = srgb(10, 10, 11)               // #0A0A0B near-black
let barHighlight = srgb(255, 255, 255, 0.14)
let checkFill = srgb(52, 199, 89)             // #34C759 Apple green
let checkMark = srgb(13, 42, 22)              // #0D2A16

// MARK: - Drawing

// Artwork is authored in a 150x150 "tile" space and scaled to fit the icon
// shape, which itself sits inside the full canvas with transparent margin
// (macOS app icons are not auto-masked, so the squircle is baked in).
let tile: CGFloat = 150
let shapeRatio: CGFloat = 0.805   // icon shape side / canvas
let cornerRatio: CGFloat = 0.2237 // Apple macOS icon corner radius ratio

func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func renderIcon(pixels: Int) -> CGImage {
    let canvas = CGFloat(pixels)
    let side = (canvas * shapeRatio).rounded()
    let margin = ((canvas - side) / 2).rounded()
    let scale = side / tile

    let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // Flip to a top-left origin so coordinates match the design.
    context.translateBy(x: 0, y: canvas)
    context.scaleBy(x: 1, y: -1)
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)

    // Background squircle.
    let shapeRect = CGRect(x: margin, y: margin, width: side, height: side)
    let cornerRadius = side * cornerRatio
    let shapePath = roundedRectPath(shapeRect, radius: cornerRadius)
    context.addPath(shapePath)
    context.setFillColor(backgroundColor)
    context.fillPath()

    if pixels >= 64 {
        context.addPath(shapePath)
        context.setStrokeColor(edgeHighlight)
        context.setLineWidth(max(1, side * 0.004))
        context.strokePath()
    }

    // Switch into tile space for the artwork.
    context.saveGState()
    context.translateBy(x: margin, y: margin)
    context.scaleBy(x: scale, y: scale)

    let showDetails = pixels >= 48 // faint context lines
    let showCheck = pixels >= 128  // green cleared check

    func fill(_ rect: CGRect, radius: CGFloat, color: CGColor) {
        context.addPath(roundedRectPath(rect, radius: radius))
        context.setFillColor(color)
        context.fillPath()
    }

    if showDetails {
        fill(CGRect(x: 24, y: 40, width: 64, height: 8), radius: 4, color: faintLineColor)
        fill(CGRect(x: 24, y: 88, width: 92, height: 8), radius: 4, color: faintLineColor)
        fill(CGRect(x: 24, y: 106, width: 54, height: 8), radius: 4, color: faintLineColor)
    }

    // The hero: opaque redaction bar snapped over one line.
    fill(CGRect(x: 18, y: 60, width: 114, height: 16), radius: 4, color: barColor)
    context.addPath(roundedRectPath(CGRect(x: 18.5, y: 60.5, width: 113, height: 15), radius: 3.5))
    context.setStrokeColor(barHighlight)
    context.setLineWidth(1)
    context.strokePath()

    if showCheck {
        context.addEllipse(in: CGRect(x: 109, y: 19, width: 22, height: 22))
        context.setFillColor(checkFill)
        context.fillPath()

        context.move(to: CGPoint(x: 115, y: 30))
        context.addLine(to: CGPoint(x: 118.2, y: 33.2))
        context.addLine(to: CGPoint(x: 124, y: 27))
        context.setStrokeColor(checkMark)
        context.setLineWidth(2.4)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }

    context.restoreGState()
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        FileHandle.standardError.write(Data("Failed to write \(url.lastPathComponent)\n".utf8))
        exit(1)
    }
}

// MARK: - Output

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outputDir = repoRoot
    .appendingPathComponent("Apps/macOSApp/Redaktr/Redaktr/Assets.xcassets/AppIcon.appiconset")

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
    let image = renderIcon(pixels: size)
    let url = outputDir.appendingPathComponent("icon_\(size).png")
    writePNG(image, to: url)
    print("Wrote \(url.lastPathComponent) (\(size)x\(size))")
}
