import Foundation

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct Command: Codable {
    enum Kind: String, Codable {
        case set, add, status, quit, enable, disable, toggle, wallpaper
    }
    var kind: Kind
    var background: Background?
    var fade: Double?
    var path: String?
}

struct Reply: Codable {
    var ok: Bool
    var message: String
}

/// Everything the agent remembers across launches.
///
/// `background` is what the overlay *would* show; `enabled` gates whether it is
/// drawn, so switching to the real wallpaper never loses the chosen background.
struct Settings: Codable {
    var enabled = true
    var background = Background.default
    var library: [String] = []
    var fit = Fit.cover

    init() {}

    /// Tolerant decoding: a state file from an older build keeps working.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        background = try container.decodeIfPresent(Background.self, forKey: .background) ?? .default
        fit = try container.decodeIfPresent(Fit.self, forKey: .fit) ?? .cover
    }

    /// What the windows should render right now.
    var effectiveBackground: Background { enabled ? background : .clear }

    mutating func remember(_ path: String) {
        library.removeAll { $0 == path }
        library.insert(path, at: 0)
        if library.count > 20 { library.removeLast(library.count - 20) }
    }
}

/// Mach-port IPC between the CLI and the running agent.
///
/// A Mach port dies with its process, so `Server.start` returning nil is a
/// reliable "another agent owns this name" and `Client.send` failing is a
/// reliable "no agent is running" — no stale lock files to reap.
enum Control {
    static let portName = "dev.nodistractions.agent" as CFString

    enum Server {
        /// Installs `handler` on the main run loop. Returns nil if the name is taken.
        static func start(_ handler: @escaping (Command) -> Reply) -> CFMessagePort? {
            Server.handler = handler
            let callback: CFMessagePortCallBack = { _, _, data, _ in
                let reply: Reply
                if let data = data as Data?,
                   let command = try? JSONDecoder().decode(Command.self, from: data) {
                    reply = Server.handler?(command) ?? Reply(ok: false, message: "agent not ready")
                } else {
                    reply = Reply(ok: false, message: "malformed command")
                }
                let encoded = (try? JSONEncoder().encode(reply)) ?? Data()
                return Unmanaged.passRetained(encoded as CFData)
            }
            guard let port = CFMessagePortCreateLocal(nil, Control.portName, callback, nil, nil) else {
                return nil
            }
            CFMessagePortSetDispatchQueue(port, .main)
            return port
        }

        private static var handler: ((Command) -> Reply)?
    }

    enum Client {
        static func send(_ command: Command) throws -> Reply {
            guard let port = CFMessagePortCreateRemote(nil, Control.portName) else {
                throw AppError("No Distractions is not running — start it with "
                    + "`nodistractions run` or open the app")
            }
            defer { CFMessagePortInvalidate(port) }
            let payload = try JSONEncoder().encode(command) as CFData
            var response: Unmanaged<CFData>?
            let status = CFMessagePortSendRequest(port, 1, payload, 2, 2,
                                                 CFRunLoopMode.defaultMode.rawValue, &response)
            guard status == Int32(kCFMessagePortSuccess) else {
                throw AppError("agent did not respond (CFMessagePort status \(status))")
            }
            guard let data = response?.takeRetainedValue() as Data? else {
                throw AppError("agent sent an empty reply")
            }
            return try JSONDecoder().decode(Reply.self, from: data)
        }
    }
}

enum State {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("No Distractions", isDirectory: true)
    }()

    static let url = State.directory.appendingPathComponent("state.json")

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: url) else { return Settings() }
        do {
            return try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            warn("ignoring unreadable state at \(url.path): \(error.localizedDescription)")
            return Settings()
        }
    }

    static func save(_ settings: Settings) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(settings).write(to: url, options: .atomic)
        } catch {
            warn("could not persist state to \(url.path): \(error.localizedDescription)")
        }
    }
}

func warn(_ message: String) {
    FileHandle.standardError.write(Data("nodistractions: \(message)\n".utf8))
}

func fail(_ message: String) -> Never {
    warn(message)
    exit(1)
}
