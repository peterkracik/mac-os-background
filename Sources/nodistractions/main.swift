import AppKit

let usage = """
No Distractions — covers the desktop wallpaper, keeps the icons

  nodistractions run                            run the agent in the foreground
  nodistractions set gradient <name>            built-in macOS-style gradient
  nodistractions set gradient <hex> <hex>        …or a custom two-colour ramp
  nodistractions set color <hex>                 …or a solid colour
  nodistractions set image <path> [--fit MODE]   …or an image
  nodistractions add                            open the image picker
  nodistractions enable | disable | toggle      overlay vs. the real wallpaper
  nodistractions status                         what is showing, and at which level
  nodistractions quit                           stop the agent
  nodistractions wallpaper <path>               set the real macOS wallpaper instead

  gradients: \(GradientPreset.all.map(\.id).joined(separator: ", "))
  --fit      cover (default) | contain | stretch | center
  --angle    custom gradient direction in degrees, CCW from +x; 270 = top→bottom
  --fade     crossfade seconds, default 0.35

The overlay sits on kCGDesktopWindowLevel: above the wallpaper, 20 levels below
the Finder icon window, and click-through — so icons stay visible and usable.
The menu bar item does the same: one Enable checkmark, Gradients ▸, Images ▸
(with Add New Image… last), and Settings ▸ Image Fit.
"""

/// Hand-rolled flag extraction: pulls `--name value` pairs out and returns the rest.
func split(_ arguments: [String]) throws -> (positional: [String], flags: [String: String]) {
    var positional: [String] = []
    var flags: [String: String] = [:]
    var index = arguments.startIndex
    while index < arguments.endIndex {
        let argument = arguments[index]
        if argument.hasPrefix("--") {
            let name = String(argument.dropFirst(2))
            guard index + 1 < arguments.endIndex else { throw AppError("--\(name) needs a value") }
            flags[name] = arguments[index + 1]
            index += 2
        } else {
            positional.append(argument)
            index += 1
        }
    }
    return (positional, flags)
}

func number(_ flags: [String: String], _ name: String, default fallback: Double) throws -> Double {
    guard let raw = flags[name] else { return fallback }
    guard let value = Double(raw) else { throw AppError("--\(name) expects a number, got '\(raw)'") }
    return value
}

func send(_ command: Command) throws {
    let reply = try Control.Client.send(command)
    guard reply.ok else { throw AppError(reply.message) }
    print(reply.message)
}

/// `set gradient` takes either a preset name or two colours.
func background(kind: String, arguments: [String], flags: [String: String]) throws -> Background {
    switch kind {
    case "gradient":
        switch arguments.count {
        case 1: return .preset(id: arguments[0])
        case 2...: return .gradient(from: arguments[0], to: arguments[1],
                                    angle: try number(flags, "angle", default: 270))
        default: throw AppError("set gradient needs a preset name or two hex colours")
        }
    case "color":
        guard let hex = arguments.first else { throw AppError("set color needs a hex value") }
        return .color(hex: hex)
    case "image":
        guard let path = arguments.first else { throw AppError("set image needs a path") }
        let fitName = flags["fit"] ?? "cover"
        guard let fit = Fit(rawValue: fitName) else {
            throw AppError("--fit expects cover | contain | stretch | center, got '\(fitName)'")
        }
        return .image(path: (path as NSString).expandingTildeInPath, fit: fit)
    default:
        throw AppError("unknown background kind '\(kind)' — try gradient | color | image")
    }
}

/// macOS 26 only grants a menu bar slot to a process with valid bundle identity,
/// so the .app must launch this exact binary as its CFBundleExecutable rather
/// than a shim. Double-clicking the app therefore arrives here with no verb.
func startAgent() -> Never {
    let agent = Agent()
    NSApplication.shared.delegate = agent
    NSApplication.shared.run()
    exit(0)
}

let launchedAsApp = Bundle.main.bundleIdentifier == "dev.nodistractions.app"

func run(_ arguments: [String]) throws {
    guard let verb = arguments.first else {
        if launchedAsApp { startAgent() }
        print(usage)
        return
    }
    let (positional, flags) = try split(Array(arguments.dropFirst()))
    let fade = try number(flags, "fade", default: 0.35)

    switch verb {
    case "run":
        startAgent()

    case "set":
        guard let kind = positional.first else {
            throw AppError("set needs gradient | color | image")
        }
        let chosen = try background(kind: kind, arguments: Array(positional.dropFirst()), flags: flags)
        try send(Command(kind: .set, background: chosen.validated(), fade: fade))

    case "enable", "disable", "toggle":
        try send(Command(kind: Command.Kind(rawValue: verb)!, fade: fade))

    case "add":
        try send(Command(kind: .add))

    case "status":
        try send(Command(kind: .status))

    case "quit":
        try send(Command(kind: .quit))

    case "wallpaper":
        guard let path = positional.first else { throw AppError("wallpaper needs a path") }
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.isReadableFile(atPath: expanded) else {
            throw AppError("no readable file at \(expanded)")
        }
        try send(Command(kind: .wallpaper, path: expanded))

    case "help", "-h", "--help":
        print(usage)

    default:
        throw AppError("unknown command '\(verb)' — try `nodistractions help`")
    }
}

do {
    try run(Array(CommandLine.arguments.dropFirst()))
} catch {
    fail(error.localizedDescription)
}
