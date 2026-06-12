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
let bgColor = NSColor(red: 0x1F / 255.0, green: 0x21 / 255.0, blue: 0x25 / 255.0, alpha: 1.0)
let tintColor = NSColor(red: 0x3F / 255.0, green: 0xB9 / 255.0, blue: 0x50 / 255.0, alpha: 1.0)
let symbolName = "arrow.triangle.pull"
let symbolPointSize: CGFloat = 440

// Output path relative to the script's working directory (repo root).
// When run via `swift Scripts/generate_icon.swift` from the repo root, FileManager.default.currentDirectoryPath is the repo root.
let outputDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Assets.xcassets/AppIcon.appiconset")

// MARK: - Size table

struct IconSize {
    let pixels: Int       // actual pixel dimension of the PNG
    let pointSize: Int    // logical point size
    let scale: Int        // @1x / @2x
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

// MARK: - Render

/// Renders the 1024×1024 master icon into an NSBitmapImageRep.
/// The approach:
///   1. Draw the dark rounded-rect background.
///   2. Obtain the SF Symbol NSImage (system symbol, template mode).
///   3. Draw it into a temporary offscreen context so we can extract pixel data.
///   4. Composite a solid green fill over the symbol using .sourceAtop so only
///      pixels that belong to the symbol glyph receive the tint — this avoids
///      NSImage template-tinting quirks that can produce incorrect colors in
///      certain OS versions.
func renderMasterIcon() -> NSBitmapImageRep {
    let size = CGFloat(canvasSize)

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: canvasSize,
        pixelsHigh: canvasSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx

    // Clear to transparent
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    // Draw dark rounded-rect background
    let offset = (size - rectSize) / 2
    let bgRect = CGRect(x: offset, y: offset, width: rectSize, height: rectSize)
    let path = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
    bgColor.setFill()
    path.fill()

    // Obtain SF Symbol at full size
    let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
    guard let rawSymbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
        fputs("ERROR: could not load SF Symbol '\(symbolName)'\n", stderr)
        exit(1)
    }

    // Render symbol into its own bitmap so we can tint with .sourceAtop
    let symW = rawSymbol.size.width
    let symH = rawSymbol.size.height

    guard let symRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(symW),
        pixelsHigh: Int(symH),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fputs("ERROR: could not create symbol bitmap rep\n", stderr)
        exit(1)
    }

    let symCtx = NSGraphicsContext(bitmapImageRep: symRep)!
    NSGraphicsContext.current = symCtx
    symCtx.cgContext.clear(CGRect(x: 0, y: 0, width: symW, height: symH))

    // Draw the symbol as a template (black mask) so .sourceAtop tinting works
    rawSymbol.isTemplate = true
    rawSymbol.draw(
        in: CGRect(x: 0, y: 0, width: symW, height: symH),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )

    // Flood the tint color over the symbol alpha mask
    tintColor.setFill()
    symCtx.cgContext.setBlendMode(.sourceAtop)
    CGRect(x: 0, y: 0, width: symW, height: symH).fill()

    // Build a tinted NSImage from the rep
    let tintedSymbol = NSImage(size: NSSize(width: symW, height: symH))
    tintedSymbol.addRepresentation(symRep)

    // Switch back to the master context and center-draw the tinted symbol
    NSGraphicsContext.current = ctx

    let symDestX = (size - symW) / 2
    let symDestY = (size - symH) / 2
    tintedSymbol.draw(
        in: CGRect(x: symDestX, y: symDestY, width: symW, height: symH),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Scales the master rep to `pixelSize`×`pixelSize` and returns a new rep.
func scale(rep: NSBitmapImageRep, to pixelSize: Int) -> NSBitmapImageRep {
    let sz = CGFloat(pixelSize)
    let srcImage = NSImage(size: rep.size)
    srcImage.addRepresentation(rep)

    let scaled = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

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
    // Simple hand-rolled JSON to avoid Foundation JSONEncoder dependency on
    // older Swift toolchains and keep the output deterministic.
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
