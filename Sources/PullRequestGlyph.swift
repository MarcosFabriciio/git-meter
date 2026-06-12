import AppKit
import CoreGraphics
import Foundation

// MARK: - Git Pull-Request Glyph
// keep in sync with Scripts/generate_icon.swift
//
// Geometry: 24×24 design box (y-down). Scaled uniformly to `rect`.
// CG is y-up; design y is flipped via cy(v) = rect.maxY - (24 - v) * s.
//
// Shape:
//   • Three hollow ring nodes: TL=(6,5), BL=(6,19), BR=(18,19)
//   • Thick vertical bar on x=6, TL→BL (gaps inside rings)
//   • Right branch: BR upward → rounded 90° corner → horizontal left → arrowhead
//   • Solid filled left-pointing arrowhead at ≈(8.5, tlY)
//
// Ring nodes are stroked with thick lines then their inner area is cleared (blend=.clear)
// so the background shows through the donut holes.

/// Draws the git pull-request glyph into `cgCtx` using `rect` as the bounding box.
/// The caller must save/restore CGState around this call if needed.
/// Colors are set internally (black fill/stroke).
nonisolated
func drawPullRequestGlyph(in cgCtx: CGContext, rect: CGRect) {
    let s = min(rect.width, rect.height) / 24.0
    let ox = rect.minX + (rect.width  - 24 * s) / 2
    let oy = rect.minY + (rect.height - 24 * s) / 2

    // Map design (x, y-down) to CG (x, y-up)
    func cx(_ v: CGFloat) -> CGFloat { ox + v * s }
    func cy(_ v: CGFloat) -> CGFloat { oy + (24 - v) * s }

    let strokeW:    CGFloat = 2.4
    let ringOuterR: CGFloat = 2.6
    let ringInnerR: CGFloat = 0.9

    let tlX: CGFloat = 6,  tlY: CGFloat = 5
    let blX: CGFloat = 6,  blY: CGFloat = 19
    let brX: CGFloat = 18, brY: CGFloat = 19

    cgCtx.setLineWidth(strokeW * s)
    cgCtx.setLineCap(.round)
    cgCtx.setLineJoin(.round)
    cgCtx.setStrokeColor(NSColor.black.cgColor)
    cgCtx.setFillColor(NSColor.black.cgColor)

    // ── Ring TL ─────────────────────────────────────────────────────────────
    cgCtx.strokeEllipse(in: CGRect(
        x: cx(tlX - ringOuterR), y: cy(tlY + ringOuterR),
        width: 2 * ringOuterR * s, height: 2 * ringOuterR * s
    ))

    // ── Ring BL ─────────────────────────────────────────────────────────────
    cgCtx.strokeEllipse(in: CGRect(
        x: cx(blX - ringOuterR), y: cy(blY + ringOuterR),
        width: 2 * ringOuterR * s, height: 2 * ringOuterR * s
    ))

    // ── Ring BR ─────────────────────────────────────────────────────────────
    cgCtx.strokeEllipse(in: CGRect(
        x: cx(brX - ringOuterR), y: cy(brY + ringOuterR),
        width: 2 * ringOuterR * s, height: 2 * ringOuterR * s
    ))

    // ── Vertical bar TL → BL ────────────────────────────────────────────────
    cgCtx.beginPath()
    cgCtx.move(to:    CGPoint(x: cx(tlX), y: cy(tlY + ringOuterR)))
    cgCtx.addLine(to: CGPoint(x: cx(blX), y: cy(blY - ringOuterR)))
    cgCtx.strokePath()

    // ── Right branch: BR up → rounded corner → left → arrowhead base ────────
    let branchStartY: CGFloat = brY - ringOuterR
    let arcR:         CGFloat = 2.0
    let cornerCX:     CGFloat = brX - arcR
    let cornerCY:     CGFloat = tlY + arcR
    let barEndX:      CGFloat = 14.0

    cgCtx.beginPath()
    cgCtx.move(to: CGPoint(x: cx(brX), y: cy(branchStartY)))
    cgCtx.addLine(to: CGPoint(x: cx(cornerCX + arcR), y: cy(cornerCY)))
    cgCtx.addArc(
        center: CGPoint(x: cx(cornerCX), y: cy(cornerCY)),
        radius: arcR * s,
        startAngle: 0,
        endAngle: .pi / 2,
        clockwise: false
    )
    cgCtx.addLine(to: CGPoint(x: cx(barEndX), y: cy(tlY)))
    cgCtx.strokePath()

    // ── Solid left-pointing arrowhead ────────────────────────────────────────
    let arrowTipX:  CGFloat = 8.5
    let arrowHalfH: CGFloat = 4.2

    cgCtx.beginPath()
    cgCtx.move(to:    CGPoint(x: cx(arrowTipX), y: cy(tlY)))
    cgCtx.addLine(to: CGPoint(x: cx(barEndX),   y: cy(tlY - arrowHalfH)))
    cgCtx.addLine(to: CGPoint(x: cx(barEndX),   y: cy(tlY + arrowHalfH)))
    cgCtx.closePath()
    cgCtx.fillPath()

    // ── Punch ring holes via .clear blend ────────────────────────────────────
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

/// Returns an `NSImage` of the git pull-request glyph suitable for use as a
/// menu bar template image (monochrome, recolored by macOS for light/dark mode).
/// `size` is in points.
nonisolated
func pullRequestTemplateImage(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    defer { img.unlockFocus() }

    guard let cgCtx = NSGraphicsContext.current?.cgContext else { return img }
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    cgCtx.clear(rect)
    drawPullRequestGlyph(in: cgCtx, rect: rect)

    img.isTemplate = true
    return img
}
