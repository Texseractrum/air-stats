import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = output.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let p = CGFloat(pixels)
    let tileRect = NSRect(x: p * 0.07, y: p * 0.07, width: p * 0.86, height: p * 0.86)
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: p * 0.19, yRadius: p * 0.19)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.shadowBlurRadius = p * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -p * 0.012)
    shadow.set()
    NSColor(calibratedRed: 0.055, green: 0.34, blue: 0.30, alpha: 1).setFill()
    tile.fill()
    NSShadow().set()
    NSGradient(colors: [NSColor(calibratedRed: 0.055, green: 0.37, blue: 0.33, alpha: 1),
                        NSColor(calibratedRed: 0.16, green: 0.70, blue: 0.57, alpha: 1)])!
        .draw(in: tile, angle: 90)

    // A quiet inset highlight gives the icon depth without compromising its silhouette.
    let inset = NSBezierPath(roundedRect: tileRect.insetBy(dx: p * 0.008, dy: p * 0.008),
                            xRadius: p * 0.182, yRadius: p * 0.182)
    inset.lineWidth = max(0.5, p * 0.002)
    NSColor.white.withAlphaComponent(0.20).setStroke()
    inset.stroke()

    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * p, y: y * p) }
    let heart = NSBezierPath()
    heart.move(to: point(0.50, 0.265))
    heart.curve(to: point(0.225, 0.610), controlPoint1: point(0.435, 0.322), controlPoint2: point(0.225, 0.470))
    heart.curve(to: point(0.50, 0.680), controlPoint1: point(0.225, 0.785), controlPoint2: point(0.415, 0.820))
    heart.curve(to: point(0.775, 0.610), controlPoint1: point(0.585, 0.820), controlPoint2: point(0.775, 0.785))
    heart.curve(to: point(0.50, 0.265), controlPoint1: point(0.775, 0.470), controlPoint2: point(0.565, 0.322))
    heart.close()
    let heartShadow = NSShadow()
    heartShadow.shadowColor = NSColor(calibratedRed: 0.02, green: 0.22, blue: 0.18, alpha: 0.35)
    heartShadow.shadowBlurRadius = p * 0.022
    heartShadow.shadowOffset = NSSize(width: 0, height: -p * 0.018)
    heartShadow.set()
    NSColor(calibratedRed: 0.89, green: 0.98, blue: 0.94, alpha: 1).setFill()
    heart.fill()
    NSShadow().set()
    NSGradient(colors: [NSColor(calibratedRed: 0.81, green: 0.95, blue: 0.88, alpha: 1), .white])!
        .draw(in: heart, angle: 90)

    // Single compact pulse, optically centered inside the heart. Simplified at 16px.
    let pulse = NSBezierPath()
    let points: [(CGFloat, CGFloat)] = [(0.305, 0.540), (0.405, 0.540), (0.455, 0.615),
                                        (0.515, 0.425), (0.570, 0.540), (0.695, 0.540)]
    pulse.move(to: point(points[0].0, points[0].1))
    for item in points.dropFirst() { pulse.line(to: point(item.0, item.1)) }
    pulse.lineWidth = max(0.8, p * 0.029)
    pulse.lineCapStyle = .round
    pulse.lineJoinStyle = .round
    NSColor(calibratedRed: 0.075, green: 0.48, blue: 0.39, alpha: 1).setStroke()
    pulse.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let bitmap = drawIcon(pixels: size * scale)
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
try drawIcon(pixels: 1024).representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("AppIcon.png"))
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
