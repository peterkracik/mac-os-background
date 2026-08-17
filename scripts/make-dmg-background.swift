// Generates Resources/DMGBackground.tiff — the disk image window's backdrop:
// an arrow from where the app sits to the Applications symlink, on the same
// palette as the icon. Run: swift scripts/make-dmg-background.swift
//
// The window's content area is 660x400 points and scripts/dmg.sh puts both
// icon centres on the y = 185 line (Finder's origin is top-left), so the
// arrow lives at y = 215 in this file's bottom-left origin. The wash stays
// light because Finder paints icon labels black in light mode and never
// adapts them to the picture.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("Resources/DMGBackground.tiff")

let width: CGFloat = 660
let height: CGFloat = 400

func color(_ hex: String, alpha: CGFloat = 1) -> NSColor {
    var digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    if digits.count == 3 { digits = digits.flatMap { [$0, $0] }.reduce(into: "") { $0.append($1) } }
    let value = UInt32(digits, radix: 16) ?? 0
    return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                   green: CGFloat((value >> 8) & 0xFF) / 255,
                   blue: CGFloat(value & 0xFF) / 255,
                   alpha: alpha)
}

func drawBackground(scale: CGFloat) {
    let canvas = CGRect(x: 0, y: 0, width: width * scale, height: height * scale)
    NSGraphicsContext.current?.imageInterpolation = .high

    // Pale wash of the Aqua palette, darker at the bottom so the icons sit
    // on something.
    NSGradient(colors: [color("#d7ebe8"), color("#f4fbfa")],
               atLocations: [0, 1], colorSpace: .sRGB)?
        .draw(in: NSBezierPath(rect: canvas), angle: 90)

    // Faint crescent watermark echoing the menu bar moon. Clipping to
    // everything-but-the-bite (even-odd) and filling the disc leaves the lune,
    // without repeating make-icon.swift's exact boundary construction.
    let moonCentre = CGPoint(x: 330 * scale, y: 306 * scale)
    let moonRadius = 58 * scale
    let offset = moonRadius * 0.72
    let biteCentre = CGPoint(x: moonCentre.x + 0.8206 * offset,
                             y: moonCentre.y + 0.5707 * offset)
    let biteRadius = moonRadius * 1.24
    let mask = NSBezierPath(rect: canvas)
    mask.appendOval(in: CGRect(x: biteCentre.x - biteRadius, y: biteCentre.y - biteRadius,
                               width: biteRadius * 2, height: biteRadius * 2))
    mask.windingRule = .evenOdd
    NSGraphicsContext.saveGraphicsState()
    mask.addClip()
    color("#0b6b74", alpha: 0.10).setFill()
    NSBezierPath(ovalIn: CGRect(x: moonCentre.x - moonRadius, y: moonCentre.y - moonRadius,
                                width: moonRadius * 2, height: moonRadius * 2)).fill()
    NSGraphicsContext.restoreGraphicsState()

    // The arrow rides the icons' centre line, app side to Applications side.
    let arrowY = (height - 185) * scale
    let teal = color("#02343a", alpha: 0.72)
    let shaft = NSBezierPath()
    shaft.move(to: CGPoint(x: 256 * scale, y: arrowY))
    shaft.line(to: CGPoint(x: 372 * scale, y: arrowY))
    shaft.lineWidth = 15 * scale
    shaft.lineCapStyle = .round
    teal.setStroke()
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: CGPoint(x: 366 * scale, y: arrowY + 26 * scale))
    head.line(to: CGPoint(x: 410 * scale, y: arrowY))
    head.line(to: CGPoint(x: 366 * scale, y: arrowY - 26 * scale))
    head.close()
    teal.setFill()
    head.fill()

    let caption = "Drag No Distractions into Applications"
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13 * scale, weight: .medium),
        .foregroundColor: color("#02343a", alpha: 0.62),
    ]
    let size = caption.size(withAttributes: attributes)
    caption.draw(at: CGPoint(x: (canvas.width - size.width) / 2, y: 30 * scale),
                 with: attributes)
}

func png(scale: Int) throws -> Data {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                    pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                    isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep)
    else { fatalError("could not allocate \(scale)x bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    drawBackground(scale: CGFloat(scale))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(scale)x PNG")
    }
    return data
}

let temporary = FileManager.default.temporaryDirectory
    .appendingPathComponent("nodistractions-dmg-background", isDirectory: true)
try? FileManager.default.removeItem(at: temporary)
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
let base = temporary.appendingPathComponent("background.png")
let retina = temporary.appendingPathComponent("background@2x.png")
try png(scale: 1).write(to: base)
try png(scale: 2).write(to: retina)

// -cathidpicheck stitches the pair into one TIFF tagged so Finder serves the
// right variant per display.
let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = ["-cathidpicheck", base.path, retina.path, "-out", output.path]
try tiffutil.run()
tiffutil.waitUntilExit()
guard tiffutil.terminationStatus == 0 else { fatalError("tiffutil failed") }
try? FileManager.default.removeItem(at: temporary)
print("wrote \(output.path)")
