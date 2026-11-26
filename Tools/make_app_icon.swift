// Generates Trip/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png (1024×1024).
// Usage: swift Tools/make_app_icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
    : "Trip/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let s = CGFloat(size)

// Sunset background
let bg = CGGradient(colorsSpace: cs, colors: [rgb(0xFFC98F), rgb(0xFB8A72), rgb(0xE9586E)] as CFArray,
                    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

// Folded map: three panels
let top: CGFloat = s * 0.66, bottom: CGFloat = s * 0.24
let xs: [CGFloat] = [s * 0.17, s * 0.39, s * 0.61, s * 0.83]
let skew: CGFloat = s * 0.035
for i in 0..<3 {
    let up = i % 2 == 0
    let path = CGMutablePath()
    path.move(to: CGPoint(x: xs[i], y: top + (up ? skew : -skew)))
    path.addLine(to: CGPoint(x: xs[i + 1], y: top + (up ? -skew : skew)))
    path.addLine(to: CGPoint(x: xs[i + 1], y: bottom + (up ? -skew : skew)))
    path.addLine(to: CGPoint(x: xs[i], y: bottom + (up ? skew : -skew)))
    path.closeSubpath()
    ctx.addPath(path)
    ctx.setFillColor(rgb(0xFFFFFF, up ? 0.97 : 0.82))
    ctx.fillPath()
}

// "Painted" blobs on the map
for (x, y, r, c) in [(0.30, 0.50, 0.075, 0x56C596), (0.50, 0.38, 0.06, 0xFFB26B), (0.70, 0.52, 0.05, 0x8EC5FC)] as [(CGFloat, CGFloat, CGFloat, UInt32)] {
    ctx.setFillColor(rgb(c, 0.9))
    ctx.fillEllipse(in: CGRect(x: s * x - s * r, y: s * y - s * r, width: s * r * 2, height: s * r * 2))
}

// Pin
let pinCenter = CGPoint(x: s * 0.5, y: s * 0.70)
let pinR = s * 0.135
let pin = CGMutablePath()
pin.addArc(center: pinCenter, radius: pinR, startAngle: .pi * 1.18, endAngle: .pi * -0.18, clockwise: true)
pin.addLine(to: CGPoint(x: s * 0.5, y: s * 0.43))
pin.closeSubpath()
ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: rgb(0x000000, 0.25))
ctx.addPath(pin)
ctx.setFillColor(rgb(0x2E3A59))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.setFillColor(rgb(0xFFFFFF))
let dot = pinR * 0.42
ctx.fillEllipse(in: CGRect(x: pinCenter.x - dot, y: pinCenter.y - dot, width: dot * 2, height: dot * 2))

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
precondition(CGImageDestinationFinalize(dest))
print("✓ wrote \(out.path)")
