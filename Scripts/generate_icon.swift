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

// Glyph occupies 60% of the badge (squircle inner rect)
let glyphFraction: CGFloat = 0.60

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

// MARK: - Git Pull-Request Glyph
// keep in sync with Sources/PullRequestGlyph.swift
//
// Strategy: render into an offscreen RGBA bitmap by:
//   A) Stroking the ring nodes and branch centerlines with thick round caps/joins
//   B) Punching holes in ring centers (clear-mode circle)
//   C) Drawing a solid filled arrowhead
// Then extract the alpha mask and use it to clip the gradient fill.
//
// Design box: 24×24 (y-down). Scale to `rect`.
// CG context passed in already has correct coordinate system (y-up).

/// Draws the git pull-request glyph into the given CGContext in black.
/// Caller is responsible for save/restore of gstate around this call.
/// Uses y-up CG coordinates; `rect` defines the bounding box.
func drawPullRequestGlyph(in cgCtx: CGContext, rect: CGRect) {
    let s = min(rect.width, rect.height) / 24.0   // uniform scale
    let ox = rect.minX + (rect.width  - 24 * s) / 2
    let oy = rect.minY + (rect.height - 24 * s) / 2

    // Map design (x, y) where y=0 is TOP to CG coords (y-up, y=0 is BOTTOM)
    func cx(_ v: CGFloat) -> CGFloat { ox + v * s }
    func cy(_ v: CGFloat) -> CGFloat { oy + (24 - v) * s }  // flip y

    // Geometry (design units, y-down)
    let strokeW: CGFloat    = 2.4    // line width (chunky)
    let ringOuterR: CGFloat = 2.6   // outer radius of donut ring
    let ringInnerR: CGFloat = 0.9   // hole radius

    // Node centers
    let tlX: CGFloat = 6, tlY: CGFloat = 5    // top-left (shifted up for more vertical room)
    let blX: CGFloat = 6, blY: CGFloat = 19   // bottom-left (shifted down)
    let brX: CGFloat = 18, brY: CGFloat = 19  // bottom-right (shifted down)

    // ── Stroke setup ───────────────────────────────────────────────────────
    cgCtx.setLineWidth(strokeW * s)
    cgCtx.setLineCap(.round)
    cgCtx.setLineJoin(.round)
    cgCtx.setStrokeColor(NSColor.black.cgColor)
    cgCtx.setFillColor(NSColor.black.cgColor)

    // ── Ring TL: stroke outer circle ───────────────────────────────────────
    cgCtx.strokeEllipse(in: CGRect(
        x: cx(tlX - ringOuterR), y: cy(tlY + ringOuterR),
        width: 2 * ringOuterR * s, height: 2 * ringOuterR * s
    ))

    // ── Ring BL: stroke outer circle ───────────────────────────────────────
    cgCtx.strokeEllipse(in: CGRect(
        x: cx(blX - ringOuterR), y: cy(blY + ringOuterR),
        width: 2 * ringOuterR * s, height: 2 * ringOuterR * s
    ))

    // ── Ring BR: stroke outer circle ───────────────────────────────────────
    cgCtx.strokeEllipse(in: CGRect(
        x: cx(brX - ringOuterR), y: cy(brY + ringOuterR),
        width: 2 * ringOuterR * s, height: 2 * ringOuterR * s
    ))

    // ── Vertical bar: TL → BL (x=6) ────────────────────────────────────────
    cgCtx.beginPath()
    cgCtx.move(to:    CGPoint(x: cx(tlX), y: cy(tlY + ringOuterR)))
    cgCtx.addLine(to: CGPoint(x: cx(blX), y: cy(blY - ringOuterR)))
    cgCtx.strokePath()

    // ── Right branch: BR up, rounded left to arrowhead base ───────────────
    // Corner center at (16, 8): 2 units left of brX, 2 units below tlY
    // Branch starts at top of BR ring, goes up to corner, turns left, ends at arrow base.
    // Branch: from top of BR ring, up to corner, then left to arrowhead base.
    // Corner center at (16, 7): the arc sits 2 units left of brX, 2 units below tlY.
    let branchStartY: CGFloat = brY - ringOuterR   // ≈ 16.4
    let arcR:         CGFloat = 2.0
    let cornerCX:     CGFloat = brX - arcR         // = 16
    let cornerCY:     CGFloat = tlY + arcR         // = 7
    let barEndX:      CGFloat = 14.0               // arrowhead base x

    cgCtx.beginPath()
    cgCtx.move(to: CGPoint(x: cx(brX), y: cy(branchStartY)))
    // Vertical up to east side of corner arc: (18, cornerCY)
    cgCtx.addLine(to: CGPoint(x: cx(cornerCX + arcR), y: cy(cornerCY)))
    // Arc: CCW from east (0) to north (+π/2) in CG y-up coords
    cgCtx.addArc(
        center: CGPoint(x: cx(cornerCX), y: cy(cornerCY)),
        radius: arcR * s,
        startAngle: 0,
        endAngle: .pi / 2,
        clockwise: false
    )
    // Horizontal left to arrowhead base at y=tlY (= cornerCY - arcR)
    cgCtx.addLine(to: CGPoint(x: cx(barEndX), y: cy(tlY)))
    cgCtx.strokePath()

    // ── Solid left-pointing arrowhead ──────────────────────────────────────
    let arrowTipX:  CGFloat = 8.5
    let arrowHalfH: CGFloat = 4.2

    cgCtx.beginPath()
    cgCtx.move(to:    CGPoint(x: cx(arrowTipX),  y: cy(tlY)))
    cgCtx.addLine(to: CGPoint(x: cx(barEndX), y: cy(tlY - arrowHalfH)))
    cgCtx.addLine(to: CGPoint(x: cx(barEndX), y: cy(tlY + arrowHalfH)))
    cgCtx.closePath()
    cgCtx.fillPath()

    // ── Punch ring holes (clear to transparent) ────────────────────────────
    // We clear the inner disc of each ring so the metal bg shows through.
    cgCtx.setBlendMode(.clear)
    cgCtx.fillEllipse(in: CGRect(
        x: cx(tlX - ringInnerR), y: cy(tlY + ringInnerR),
        width: 2 * ringInnerR * s, height: 2 * ringInnerR * s
    ))
    cgCtx.fillEllipse(in: CGRect(
        x: cx(blX - ringInnerR), y: cy(blY + ringInnerR),
        width: 2 * ringInnerR * s, height: 2 * ringInnerR * s
    ))
    cgCtx.fillEllipse(in: CGRect(
        x: cx(brX - ringInnerR), y: cy(brY + ringInnerR),
        width: 2 * ringInnerR * s, height: 2 * ringInnerR * s
    ))
    cgCtx.setBlendMode(.normal)
}

// MARK: - Render

/// Renders the 1024×1024 master icon into an NSBitmapImageRep.
///
/// Pipeline:
///   1. Draw the squircle with a vertical dark metal CGGradient.
///   2. Faint inner highlight along the top edge.
///   3. Render the custom glyph into a scratch RGBA bitmap (black + holes).
///   4. Extract the alpha channel as an 8-bit grayscale CGImage mask.
///   5. Clip the master context to the glyph mask.
///   6. Draw the green gradient — lands only on glyph-covered pixels.
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

    // ── 3. Render glyph into scratch RGBA bitmap ────────────────────────────
    let glyphSize = Int(rectSize * glyphFraction)
    let maskRep = makeBitmapRep(width: glyphSize, height: glyphSize)
    let maskNSCtx = NSGraphicsContext(bitmapImageRep: maskRep)!
    maskNSCtx.cgContext.clear(CGRect(x: 0, y: 0, width: CGFloat(glyphSize), height: CGFloat(glyphSize)))
    drawPullRequestGlyph(
        in: maskNSCtx.cgContext,
        rect: CGRect(x: 0, y: 0, width: CGFloat(glyphSize), height: CGFloat(glyphSize))
    )

    // ── 4. Extract alpha channel as CGImage mask ────────────────────────────
    guard let srcData = maskRep.bitmapData else {
        fputs("ERROR: could not access bitmap data\n", stderr)
        exit(1)
    }
    let srcBytesPerRow   = maskRep.bytesPerRow
    let srcSamplesPerPix = maskRep.samplesPerPixel
    var alphaData = [UInt8](repeating: 0, count: glyphSize * glyphSize)

    for yy in 0 ..< glyphSize {
        for xx in 0 ..< glyphSize {
            let srcOff = yy * srcBytesPerRow + xx * srcSamplesPerPix
            let alpha  = srcData[srcOff + 3]
            alphaData[yy * glyphSize + xx] = 255 - alpha   // mask convention: 0=let through
        }
    }

    let dataProvider = CGDataProvider(data: NSData(bytes: &alphaData, length: alphaData.count))!
    let alphaMask = CGImage(
        maskWidth: glyphSize,
        height: glyphSize,
        bitsPerComponent: 8,
        bitsPerPixel: 8,
        bytesPerRow: glyphSize,
        provider: dataProvider,
        decode: nil,
        shouldInterpolate: true
    )!

    // ── 5+6. Clip to glyph alpha, draw green gradient ───────────────────────
    let glyphSizef = rectSize * glyphFraction
    let glyphX = offset + (rectSize - glyphSizef) / 2
    let glyphY = offset + (rectSize - glyphSizef) / 2
    let glyphRect = CGRect(x: glyphX, y: glyphY, width: glyphSizef, height: glyphSizef)

    cgCtx.saveGState()
    cgCtx.clip(to: glyphRect, mask: alphaMask)

    let glyphGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [glyphTopColor.cgColor, glyphBottomColor.cgColor] as CFArray,
        locations: [0.0, 1.0]
    )!
    cgCtx.drawLinearGradient(
        glyphGradient,
        start: CGPoint(x: glyphRect.midX, y: glyphRect.maxY),
        end:   CGPoint(x: glyphRect.midX, y: glyphRect.minY),
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
