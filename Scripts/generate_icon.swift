#!/usr/bin/env swift

// generate_icon.swift
// Run: swift Scripts/generate_icon.swift
// Writes all required macOS AppIcon PNGs to Assets.xcassets/AppIcon.appiconset/
// and generates Contents.json.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Config

let canvasSize = 1024
let rectSize: CGFloat = 824
let cornerRadius: CGFloat = 185

// Metal gradient: top charcoal → bottom near-black (vertical, top = lighter)
let bgTopColor    = NSColor(red: 0x34 / 255.0, green: 0x37 / 255.0, blue: 0x3B / 255.0, alpha: 1.0)
let bgBottomColor = NSColor(red: 0x16 / 255.0, green: 0x17 / 255.0, blue: 0x19 / 255.0, alpha: 1.0)

// Glyph gradient: light green top → deep GitHub green bottom
let glyphTopColor    = NSColor(red: 0xA5 / 255.0, green: 0xF0 / 255.0, blue: 0xB0 / 255.0, alpha: 1.0)
let glyphBottomColor = NSColor(red: 0x2E / 255.0, green: 0xA0 / 255.0, blue: 0x43 / 255.0, alpha: 1.0)

let symbolName = "arrow.triangle.pull"
let symbolPointSize: CGFloat = 440

// Output path relative to the script's working directory (repo root).
let outputDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Assets.xcassets/AppIcon.appiconset")

// MARK: - Size table

struct IconSize {
    let pixels: Int
    let pointSize: Int
    let scale: Int
    let filename: String
}

let sizes: [IconSize] = [
    IconSize(pixels: 16,   pointSize: 16,  scale: 1, filename: "icon_16x16.png"),
    IconSize(pixels: 32,   pointSize: 16,  scale: 2, filename: "icon_16x16@2x.png"),
    IconSize(pixels: 32,   pointSize: 32,  scale: 1, filename: "icon_32x32.png"),
    IconSize(pixels: 64,   pointSize: 32,  scale: 2, filename: "icon_32x32@2x.png"),
    IconSize(pixels: 128,  pointSize: 128, scale: 1, filename: "icon_128x128.png"),
    IconSize(pixels: 256,  pointSize: 128, scale: 2, filename: "icon_128x128@2x.png"),
    IconSize(pixels: 256,  pointSize: 256, scale: 1, filename: "icon_256x256.png"),
    IconSize(pixels: 512,  pointSize: 256, scale: 2, filename: "icon_256x256@2x.png"),
    IconSize(pixels: 512,  pointSize: 512, scale: 1, filename: "icon_512x512.png"),
    IconSize(pixels: 1024, pointSize: 512, scale: 2, filename: "icon_512x512@2x.png"),
]

// MARK: - Helpers

func makeBitmapRep(width: Int, height: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
}

/// Extracts the alpha channel of `source` as a 1-channel CGImage mask
/// suitable for use with CGContext.clip(to:mask:).
///
/// CGImage mask convention: 0 = let through (opaque), 255 = block (transparent).
/// This is the photographic negative of intuition, so we invert: glyph alpha 255
/// becomes 0 (let through), transparent alpha 0 becomes 255 (block).
func alphaOnlyMaskImage(from source: NSBitmapImageRep, width: Int, height: Int) -> CGImage {
    let bytesPerRow = width
    var alphaData = [UInt8](repeating: 0, count: width * height)

    guard let srcData = source.bitmapData else {
        fputs("ERROR: could not access bitmap data\n", stderr)
        exit(1)
    }
    let srcBytesPerRow = source.bytesPerRow
    let samplesPerPixel = source.samplesPerPixel

    for y in 0 ..< height {
        for x in 0 ..< width {
            let srcOffset = y * srcBytesPerRow + x * samplesPerPixel
            let alpha = srcData[srcOffset + 3]
            // Invert: opaque glyph pixel → 0 (let through); transparent → 255 (block)
            alphaData[y * bytesPerRow + x] = 255 - alpha
        }
    }

    let dataProvider = CGDataProvider(
        data: NSData(bytes: &alphaData, length: alphaData.count)
    )!

    return CGImage(
        maskWidth: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 8,
        bytesPerRow: bytesPerRow,
        provider: dataProvider,
        decode: nil,
        shouldInterpolate: true
    )!
}

// MARK: - Render

/// Renders the 1024×1024 master icon into an NSBitmapImageRep.
///
/// Pipeline:
///   1. Draw the squircle with a vertical dark metal CGGradient.
///   2. Faint inner highlight along the top edge.
///   3. Render the SF Symbol into a full RGBA bitmap (black glyph, clear bg).
///   4. Extract the alpha channel as an 8-bit grayscale CGImage mask.
///   5. Clip the master context to the glyph mask using clip(to:mask:).
///   6. Draw the green gradient — it lands only on glyph-covered pixels.
///   7. Reset clip.
func renderMasterIcon() -> NSBitmapImageRep {
    let size = CGFloat(canvasSize)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    let rep = makeBitmapRep(width: canvasSize, height: canvasSize)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cgCtx = ctx.cgContext

    cgCtx.clear(CGRect(x: 0, y: 0, width: size, height: size))

    // ── 1. Metal gradient squircle ──────────────────────────────────────────
    let offset = (size - rectSize) / 2
    let bgRect = CGRect(x: offset, y: offset, width: rectSize, height: rectSize)
    let squirclePath = CGPath(
        roundedRect: bgRect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )

    cgCtx.saveGState()
    cgCtx.addPath(squirclePath)
    cgCtx.clip()

    let bgGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [bgTopColor.cgColor, bgBottomColor.cgColor] as CFArray,
        locations: [0.0, 1.0]
    )!
    // CG y-up: maxY = visual top, minY = visual bottom
    cgCtx.drawLinearGradient(
        bgGradient,
        start: CGPoint(x: bgRect.midX, y: bgRect.maxY),
        end:   CGPoint(x: bgRect.midX, y: bgRect.minY),
        options: []
    )

    // ── 2. 1px inner top highlight ──────────────────────────────────────────
    cgCtx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.08))
    cgCtx.setLineWidth(2.0)
    cgCtx.addPath(squirclePath)
    cgCtx.strokePath()

    cgCtx.restoreGState()

    // ── 3. Render SF Symbol into RGBA bitmap ────────────────────────────────
    let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
    guard let rawSymbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
        fputs("ERROR: could not load SF Symbol '\(symbolName)'\n", stderr)
        exit(1)
    }

    let symW = Int(rawSymbol.size.width)
    let symH = Int(rawSymbol.size.height)

    let maskRep = makeBitmapRep(width: symW, height: symH)
    let maskNSCtx = NSGraphicsContext(bitmapImageRep: maskRep)!
    NSGraphicsContext.current = maskNSCtx
    maskNSCtx.cgContext.clear(CGRect(x: 0, y: 0, width: CGFloat(symW), height: CGFloat(symH)))
    // Draw WITHOUT isTemplate so the alpha channel carries correct opaque/transparent data.
    // Template mode produces all-transparent output in RGBA context.
    rawSymbol.draw(
        in: CGRect(x: 0, y: 0, width: CGFloat(symW), height: CGFloat(symH)),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )

    // ── 4. Extract alpha channel as a CGImage mask ──────────────────────────
    let alphaMask = alphaOnlyMaskImage(from: maskRep, width: symW, height: symH)

    // ── 5+6. Clip to glyph alpha, draw green gradient ───────────────────────
    NSGraphicsContext.current = ctx

    let symDestX = (size - CGFloat(symW)) / 2
    let symDestY = (size - CGFloat(symH)) / 2
    let symDestRect = CGRect(x: symDestX, y: symDestY, width: CGFloat(symW), height: CGFloat(symH))

    cgCtx.saveGState()
    // clip(to:mask:) uses the mask image as an alpha clip — white = opaque, black = clipped.
    cgCtx.clip(to: symDestRect, mask: alphaMask)

    let glyphGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [glyphTopColor.cgColor, glyphBottomColor.cgColor] as CFArray,
        locations: [0.0, 1.0]
    )!
    // CG y-up: maxY = visual top, minY = visual bottom
    cgCtx.drawLinearGradient(
        glyphGradient,
        start: CGPoint(x: symDestRect.midX, y: symDestRect.maxY),
        end:   CGPoint(x: symDestRect.midX, y: symDestRect.minY),
        options: []
    )

    cgCtx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Scales the master rep to `pixelSize`×`pixelSize` and returns a new rep.
func scale(rep: NSBitmapImageRep, to pixelSize: Int) -> NSBitmapImageRep {
    let sz = CGFloat(pixelSize)
    let srcImage = NSImage(size: rep.size)
    srcImage.addRepresentation(rep)

    let scaled = makeBitmapRep(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: scaled)!
    NSGraphicsContext.current = ctx
    ctx.cgContext.clear(CGRect(x: 0, y: 0, width: sz, height: sz))
    srcImage.draw(
        in: CGRect(x: 0, y: 0, width: sz, height: sz),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()
    return scaled
}

// MARK: - Contents.json

func contentsJSON(sizes: [IconSize]) -> String {
    var images: [[String: String]] = []
    for s in sizes {
        images.append([
            "filename": s.filename,
            "idiom": "mac",
            "scale": "\(s.scale)x",
            "size": "\(s.pointSize)x\(s.pointSize)"
        ])
    }
    var lines = ["{", "  \"images\" : ["]
    for (i, img) in images.enumerated() {
        let comma = i < images.count - 1 ? "," : ""
        lines += [
            "    {",
            "      \"filename\" : \"\(img["filename"]!)\",",
            "      \"idiom\" : \"\(img["idiom"]!)\",",
            "      \"scale\" : \"\(img["scale"]!)\",",
            "      \"size\" : \"\(img["size"]!)\"",
            "    }\(comma)"
        ]
    }
    lines += [
        "  ],",
        "  \"info\" : {",
        "    \"author\" : \"xcode\",",
        "    \"version\" : 1",
        "  }",
        "}"
    ]
    return lines.joined(separator: "\n") + "\n"
}

// MARK: - Main

print("Rendering master 1024×1024 icon…")
let master = renderMasterIcon()
print("  Master rendered: \(master.pixelsWide)×\(master.pixelsHigh)")

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

for s in sizes {
    let rep = s.pixels == canvasSize ? master : scale(rep: master, to: s.pixels)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fputs("ERROR: PNG encoding failed for \(s.filename)\n", stderr)
        exit(1)
    }
    let dest = outputDir.appendingPathComponent(s.filename)
    try png.write(to: dest)
    print("  Wrote \(s.filename) (\(s.pixels)×\(s.pixels))")
}

let jsonPath = outputDir.appendingPathComponent("Contents.json")
try contentsJSON(sizes: sizes).write(to: jsonPath, atomically: true, encoding: .utf8)
print("  Wrote Contents.json")
print("Done. Output → \(outputDir.path)")
