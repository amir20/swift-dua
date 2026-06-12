import CoreGraphics
// Generates the "Halo" app icon: a donut ring in the app's own oklch
// palette on a soft warm card, with the signature amber reclaim accent.
//
//   swift Icons/make-icon.swift <out.png> [size]
//
// Produces a single PNG; `make-icon.sh` rasterizes it into the .iconset/.icns.
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// oklch → sRGB (0–1), the same conversion the app's Palette uses.
func oklch(_ L: Double, _ c: Double, _ hDeg: Double) -> (Double, Double, Double) {
    let h = hDeg * .pi / 180
    let a = c * cos(h)
    let b = c * sin(h)
    let l_ = L + 0.3963377774 * a + 0.2158037573 * b
    let m_ = L - 0.1055613458 * a - 0.0638541728 * b
    let s_ = L - 0.0894841775 * a - 1.2914855480 * b
    let l = l_ * l_ * l_
    let m = m_ * m_ * m_
    let s = s_ * s_ * s_
    let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    let bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    func gamma(_ v: Double) -> Double {
        let cc = max(0, min(1, v))
        return cc <= 0.0031308 ? 12.92 * cc : 1.055 * pow(cc, 1 / 2.4) - 0.055
    }
    return (gamma(r), gamma(g), gamma(bl))
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <out.png> [size]\n".utf8))
    exit(1)
}
let outPath = args[1]
let S = args.count >= 3 ? Int(args[2]) ?? 1024 : 1024
let size = CGFloat(S)

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setShouldAntialias(true)
ctx.interpolationQuality = .high

func cg(_ rgb: (Double, Double, Double), _ a: Double = 1) -> CGColor {
    CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: a)
}

let cx = size / 2
let cy = size / 2
func scale(_ v: CGFloat) -> CGFloat { v / 1024 * size }  // geometry authored at 1024

// 1. Rounded-rect card with a soft top-down gradient.
let margin = scale(44)
let rect = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
let bg = CGPath(
    roundedRect: rect, cornerWidth: scale(226), cornerHeight: scale(226), transform: nil)
ctx.saveGState()
ctx.addPath(bg)
ctx.clip()
let grad = CGGradient(
    colorsSpace: cs,
    colors: [cg(oklch(0.995, 0.003, 95)), cg(oklch(0.93, 0.014, 70))] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
ctx.restoreGState()

// Point on a circle: phi measured clockwise from 12 o'clock.
func point(_ phi: CGFloat, _ r: CGFloat) -> CGPoint {
    CGPoint(x: cx + r * sin(phi), y: cy + r * cos(phi))
}

func wedge(_ a0: CGFloat, _ a1: CGFloat, _ ri: CGFloat, _ ro: CGFloat, _ color: CGColor) {
    let p = CGMutablePath()
    let steps = max(2, Int((a1 - a0) / 0.015))
    p.move(to: point(a0, ro))
    for i in 0...steps { p.addLine(to: point(a0 + (a1 - a0) * CGFloat(i) / CGFloat(steps), ro)) }
    for i in 0...steps { p.addLine(to: point(a1 - (a1 - a0) * CGFloat(i) / CGFloat(steps), ri)) }
    p.closeSubpath()
    ctx.addPath(p)
    ctx.setFillColor(color)
    ctx.fillPath()
}

// 2. The donut: segments in the real category palette.
let rOut = scale(334)
let rIn = scale(206)
let segs: [((Double, Double, Double), CGFloat)] = [
    (oklch(0.80, 0.115, 85), 0.24),  // deps — amber
    (oklch(0.70, 0.115, 25), 0.19),  // media — coral
    (oklch(0.79, 0.085, 205), 0.15),  // cache — cyan
    (oklch(0.74, 0.095, 152), 0.13),  // code — green
    (oklch(0.66, 0.105, 252), 0.12),  // build — blue
    (oklch(0.62, 0.10, 300), 0.09),  // container — violet
    (oklch(0.83, 0.012, 75), 0.08),  // other — warm gray
]
let twoPi = CGFloat.pi * 2
let gap: CGFloat = 0.035
var phi: CGFloat = 0
for (color, frac) in segs {
    let span = frac * twoPi
    wedge(phi + gap / 2, phi + span - gap / 2, rIn, rOut, cg(color))
    phi += span
}

// 3. Outer amber "reclaim" accent arc, sweeping from 12 o'clock.
wedge(gap / 2, 0.36 * twoPi, rOut + scale(12), rOut + scale(24), cg(oklch(0.66, 0.15, 58)))

// 4. Soft inner disc so the hole reads cleanly.
ctx.setFillColor(cg(oklch(0.995, 0.003, 95)))
ctx.fillEllipse(
    in: CGRect(
        x: cx - rIn + scale(2), y: cy - rIn + scale(2),
        width: 2 * (rIn - scale(2)), height: 2 * (rIn - scale(2))))

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: outPath)
guard
    let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
else {
    FileHandle.standardError.write(Data("could not create PNG destination\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write(Data("could not write PNG\n".utf8))
    exit(1)
}
print("wrote \(outPath) (\(S)×\(S))")
