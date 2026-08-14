// Generates Resources/AppIcon.icns from code, so the icon always matches the
// app's own Aqua gradient. Run: swift scripts/make-icon.swift
//
// Geometry follows Apple's macOS icon grid: a 1024 canvas whose artwork
// occupies the middle 824pt with a ~22.5% corner radius, plus a soft contact
// shadow. Every size is drawn natively rather than downscaled, so the 16pt
// version keeps clean edges.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset")
let icns = root.appendingPathComponent("Resources/AppIcon.icns")

func color(_ hex: String, alpha: CGFloat = 1) -> NSColor {
    var digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    if digits.count == 3 { digits = digits.flatMap { [$0, $0] }.reduce(into: "") { $0.append($1) } }
    let value = UInt32(digits, radix: 16) ?? 0
    return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                   green: CGFloat((value >> 8) & 0xFF) / 255,
                   blue: CGFloat(value & 0xFF) / 255,
                   alpha: alpha)
}

/// Four-pointed sparkle with concave sides.
func sparkle(at center: CGPoint, radius: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let k = radius * 0.2
    let tips = [CGPoint(x: center.x, y: center.y + radius),
                CGPoint(x: center.x + radius, y: center.y),
                CGPoint(x: center.x, y: center.y - radius),
                CGPoint(x: center.x - radius, y: center.y)]
    path.move(to: tips[0])
    for index in 0..<4 {
        let from = tips[index], to = tips[(index + 1) % 4]
        let control = CGPoint(x: center.x + (from.x - center.x + to.x - center.x) / radius * k,
                              y: center.y + (from.y - center.y + to.y - center.y) / radius * k)
        path.curve(to: to, controlPoint1: control, controlPoint2: control)
    }
    path.close()
    return path
}

/// The lune left when `bite` is subtracted from the moon disc.
///
/// Even-odd filling two overlapping circles yields their symmetric difference —
/// two lunes — which reads as a Venn diagram, so the boundary is built from the
/// circles' two intersection points instead: the outer arc that stays away from
/// the bite, then the bite's arc that cuts back through the disc.
func crescent(centre: CGPoint, radius: CGFloat,
              biteCentre: CGPoint, biteRadius: CGFloat) -> NSBezierPath {
    let span = CGPoint(x: biteCentre.x - centre.x, y: biteCentre.y - centre.y)
    let distance = (span.x * span.x + span.y * span.y).squareRoot()
    let unit = CGPoint(x: span.x / distance, y: span.y / distance)

    let along = (distance * distance + radius * radius - biteRadius * biteRadius) / (2 * distance)
    let across = (radius * radius - along * along).squareRoot()
    let foot = CGPoint(x: centre.x + unit.x * along, y: centre.y + unit.y * along)
    let normal = CGPoint(x: -unit.y, y: unit.x)
    let hit = (CGPoint(x: foot.x + normal.x * across, y: foot.y + normal.y * across),
               CGPoint(x: foot.x - normal.x * across, y: foot.y - normal.y * across))

    func angle(_ point: CGPoint, from origin: CGPoint) -> CGFloat {
        atan2(point.y - origin.y, point.x - origin.x)
    }

    /// Sweep from `start` to `end` the way whose midpoint faces away from the bite.
    func sweep(from start: CGFloat, to end: CGFloat) -> CGFloat {
        var delta = end - start
        while delta <= -.pi { delta += 2 * .pi }
        while delta > .pi { delta -= 2 * .pi }
        let mid = start + delta / 2
        return cos(mid) * unit.x + sin(mid) * unit.y < 0 ? delta : delta - (delta > 0 ? 2 : -2) * .pi
    }

    func arc(_ path: NSBezierPath, origin: CGPoint, radius: CGFloat, from: CGFloat, delta: CGFloat) {
        let steps = 180
        for step in 0...steps {
            let theta = from + delta * CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: origin.x + cos(theta) * radius, y: origin.y + sin(theta) * radius)
            if path.isEmpty { path.move(to: point) } else { path.line(to: point) }
        }
    }

    let path = NSBezierPath()
    let outerStart = angle(hit.0, from: centre), outerEnd = angle(hit.1, from: centre)
    arc(path, origin: centre, radius: radius,
        from: outerStart, delta: sweep(from: outerStart, to: outerEnd))
    let biteStart = angle(hit.1, from: biteCentre), biteEnd = angle(hit.0, from: biteCentre)
    arc(path, origin: biteCentre, radius: biteRadius,
        from: biteStart, delta: sweep(from: biteStart, to: biteEnd))
    path.close()
    return path
}

func drawIcon(size: CGFloat) {
    let margin = size * 100 / 1024
    let plate = CGRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
    let radius = plate.width * 0.225
    let shape = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)

    NSGraphicsContext.current?.imageInterpolation = .high

    // Contact shadow under the plate.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color("#000000", alpha: 0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.008)
    shadow.shadowBlurRadius = size * 0.024
    shadow.set()
    color("#000203").setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.setClip()

    // Same ramp as the Aqua preset: provided primary into near-black, on hue.
    let ramp = NSGradient(colors: [color("#034a52"), color("#02343a"), color("#011014"), color("#000203")],
                          atLocations: [0, 0.34, 0.7, 1], colorSpace: .sRGB)
    ramp?.draw(in: shape, angle: 45)

    // Corner glow, echoing the preset's radial highlight.
    let glowCentre = CGPoint(x: plate.minX + plate.width * 0.12, y: plate.minY + plate.height * 0.1)
    NSGradient(colors: [color("#034a52", alpha: 0.85), color("#034a52", alpha: 0)],
               atLocations: [0, 1], colorSpace: .sRGB)?
        .draw(fromCenter: glowCentre, radius: 0,
              toCenter: glowCentre, radius: plate.width * 0.62, options: [])

    // Crescent moon, upper right.
    let moonRadius = plate.width * 0.185
    let moonCentre = CGPoint(x: plate.midX + plate.width * 0.055, y: plate.midY + plate.height * 0.105)
    // Thickness along the axis is radius + distance − biteRadius, so these keep
    // roughly half the disc. Bite pushed up and right, crescent opens lower-left.
    let (unitX, unitY) = (0.82 / 0.9987, 0.57 / 0.9987) as (CGFloat, CGFloat)
    let offset = moonRadius * 0.72
    let moon = crescent(centre: moonCentre, radius: moonRadius,
                        biteCentre: CGPoint(x: moonCentre.x + unitX * offset,
                                            y: moonCentre.y + unitY * offset),
                        biteRadius: moonRadius * 1.24)
    color("#cfeeea", alpha: 0.94).setFill()
    moon.fill()

    // Sparkles, left of the moon, sized down as they recede.
    let sparkles: [(CGPoint, CGFloat)] = [
        (CGPoint(x: plate.minX + plate.width * 0.24, y: plate.minY + plate.height * 0.735), 0.05),
        (CGPoint(x: plate.minX + plate.width * 0.335, y: plate.minY + plate.height * 0.565), 0.031),
        (CGPoint(x: plate.minX + plate.width * 0.165, y: plate.minY + plate.height * 0.545), 0.023),
    ]
    for (centre, scale) in sparkles {
        color("#9fe0d8", alpha: 0.9).setFill()
        sparkle(at: centre, radius: plate.width * scale).fill()
    }

    NSGraphicsContext.restoreGraphicsState()

    // Hairline rim so the plate reads against a dark wallpaper.
    let rim = NSBezierPath(roundedRect: plate.insetBy(dx: size * 0.001, dy: size * 0.001),
                           xRadius: radius, yRadius: radius)
    rim.lineWidth = max(1, size * 0.002)
    color("#7fd0c8", alpha: 0.18).setStroke()
    rim.stroke()
}

func png(size: Int) throws -> Data {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                    isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep)
    else { fatalError("could not allocate \(size)px bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    drawIcon(size: CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(size)px PNG")
    }
    return data
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// iconutil's expected names: base point size plus @2x variants.
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

// Keep a full-size preview around for the README.
try png(size: 1024).write(to: root.appendingPathComponent("Resources/icon-1024.png"))
print("wrote \(icns.path)")
