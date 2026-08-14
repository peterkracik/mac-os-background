import AppKit

/// How an image is mapped onto a screen-sized layer.
enum Fit: String, Codable {
    case cover, contain, stretch, center

    var contentsGravity: CALayerContentsGravity {
        switch self {
        case .cover: return .resizeAspectFill
        case .contain: return .resizeAspect
        case .stretch: return .resize
        case .center: return .center
        }
    }
}

/// A built-in gradient in the macOS idiom: a deep, desaturated multi-stop base
/// with one soft off-centre glow, rather than a hard two-colour ramp.
struct GradientPreset {
    let id: String
    let title: String
    /// Degrees counter-clockwise from +x; 270 runs top → bottom.
    let angle: Double
    let stops: [(hex: String, at: Double)]
    /// Radial highlight: colour carries its own alpha, centre and radius are
    /// fractions of the screen.
    let glow: (hex: String, center: CGPoint, radius: Double)?

    static let all: [GradientPreset] = [
        // Default: the provided primary #034a52 in the bottom-left corner,
        // ramping along the diagonal into near-black kept on the same hue.
        GradientPreset(id: "aqua", title: "Aqua", angle: 45,
                       stops: [("#034a52", 0), ("#02343a", 0.13), ("#021f23", 0.29),
                               ("#011014", 0.5), ("#000709", 0.75), ("#000203", 1)],
                       glow: ("#034a5266", CGPoint(x: 0.06, y: 0.05), 0.4)),
        GradientPreset(id: "midnight", title: "Midnight", angle: 250,
                       stops: [("#06080f", 0), ("#101833", 0.55), ("#1b2547", 1)],
                       glow: ("#4257a88c", CGPoint(x: 0.72, y: 0.88), 0.85)),
        GradientPreset(id: "graphite", title: "Graphite", angle: 265,
                       stops: [("#17171a", 0), ("#232327", 0.5), ("#303036", 1)],
                       glow: nil),
        GradientPreset(id: "aurora", title: "Aurora", angle: 255,
                       stops: [("#04121c", 0), ("#0b3242", 0.5), ("#12525a", 1)],
                       glow: ("#2fbfa87a", CGPoint(x: 0.22, y: 0.9), 0.8)),
        GradientPreset(id: "dusk", title: "Dusk", angle: 260,
                       stops: [("#140d1c", 0), ("#35203c", 0.55), ("#5e3348", 1)],
                       glow: ("#e2915f70", CGPoint(x: 0.8, y: 0.12), 0.75)),
    ]

    static func named(_ id: String) -> GradientPreset? {
        all.first { $0.id == id }
    }
}

/// What the overlay draws. `clear` means "get out of the way and show the real
/// wallpaper".
enum Background: Codable, Equatable {
    case clear
    case preset(id: String)
    case color(hex: String)
    case gradient(from: String, to: String, angle: Double)
    case image(path: String, fit: Fit)

    /// What a fresh install shows, and what enabling falls back to.
    static let `default` = Background.preset(id: GradientPreset.all[0].id)

    var summary: String {
        switch self {
        case .clear: return "no background"
        case .preset(let id): return "gradient \(GradientPreset.named(id)?.title ?? id)"
        case .color(let hex): return "color \(hex)"
        case .gradient(let a, let b, let angle): return "gradient \(a) → \(b) @\(Int(angle))°"
        case .image(let path, let fit): return "image \((path as NSString).lastPathComponent) (\(fit.rawValue))"
        }
    }

    /// Validates every field so bad input fails in the CLI, not silently inside the agent.
    func validated() throws -> Background {
        switch self {
        case .clear:
            return self
        case .preset(let id):
            guard GradientPreset.named(id) != nil else {
                throw AppError("unknown gradient '\(id)' — try "
                    + GradientPreset.all.map(\.id).joined(separator: ", "))
            }
        case .color(let hex):
            _ = try Background.parseColor(hex)
        case .gradient(let a, let b, _):
            _ = try Background.parseColor(a)
            _ = try Background.parseColor(b)
        case .image(let path, _):
            guard FileManager.default.isReadableFile(atPath: path) else {
                throw AppError("no readable file at \(path)")
            }
            guard NSImage(contentsOfFile: path) != nil else {
                throw AppError("\(path) is not an image macOS can decode")
            }
        }
        return self
    }

    /// `#rgb`, `#rrggbb`, `#rrggbbaa`, with or without the leading `#`.
    static func parseColor(_ text: String) throws -> NSColor {
        var digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        if digits.count == 3 {
            digits = digits.flatMap { [$0, $0] }.reduce(into: "") { $0.append($1) }
        }
        guard digits.count == 6 || digits.count == 8,
              let value = UInt32(digits, radix: 16)
        else {
            throw AppError("bad color '\(text)' — expected #rgb, #rrggbb or #rrggbbaa")
        }
        let hasAlpha = digits.count == 8
        let shift: UInt32 = hasAlpha ? 8 : 0
        let component = { (byte: UInt32) in CGFloat((value >> byte) & 0xFF) / 255 }
        return NSColor(srgbRed: component(16 + shift),
                       green: component(8 + shift),
                       blue: component(shift),
                       alpha: hasAlpha ? component(0) : 1)
    }

    /// Gradient direction as layer-space endpoints.
    private static func endpoints(angle: Double) -> (start: CGPoint, end: CGPoint) {
        let radians = angle * .pi / 180
        let dx = cos(radians) / 2, dy = sin(radians) / 2
        return (CGPoint(x: 0.5 - dx, y: 0.5 - dy), CGPoint(x: 0.5 + dx, y: 0.5 + dy))
    }

    /// Builds the layer that renders this background. `nil` for `.clear`.
    func makeLayer(scale: CGFloat) -> CALayer? {
        switch self {
        case .clear:
            return nil

        case .preset(let id):
            guard let preset = GradientPreset.named(id) else { return nil }
            let container = CALayer()

            let base = CAGradientLayer()
            base.colors = preset.stops.compactMap { (try? Background.parseColor($0.hex))?.cgColor }
            base.locations = preset.stops.map { NSNumber(value: $0.at) }
            (base.startPoint, base.endPoint) = Background.endpoints(angle: preset.angle)
            container.addSublayer(base)

            if let glow = preset.glow, let color = try? Background.parseColor(glow.hex) {
                let halo = CAGradientLayer()
                halo.type = .radial
                // Same RGB at zero alpha, so the falloff never greys out.
                halo.colors = [color.cgColor, color.withAlphaComponent(0).cgColor]
                halo.locations = [0, 1]
                halo.startPoint = glow.center
                halo.endPoint = CGPoint(x: glow.center.x + glow.radius,
                                        y: glow.center.y + glow.radius)
                container.addSublayer(halo)
            }
            return container

        case .color(let hex):
            let layer = CALayer()
            layer.backgroundColor = (try? Background.parseColor(hex))?.cgColor
            return layer

        case .gradient(let from, let to, let angle):
            let layer = CAGradientLayer()
            layer.colors = [try? Background.parseColor(from), try? Background.parseColor(to)]
                .compactMap { $0?.cgColor }
            (layer.startPoint, layer.endPoint) = Background.endpoints(angle: angle)
            return layer

        case .image(let path, let fit):
            let layer = CALayer()
            layer.contents = NSImage(contentsOfFile: path)?
                .cgImage(forProposedRect: nil, context: nil, hints: nil)
            layer.contentsGravity = fit.contentsGravity
            layer.contentsScale = scale
            layer.masksToBounds = true
            layer.backgroundColor = NSColor.black.cgColor // letterbox for .contain / .center
            return layer
        }
    }
}
