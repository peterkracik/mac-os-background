import AppKit
import UniformTypeIdentifiers

/// The background agent: one wallpaper-level window per screen, plus a menu bar item.
final class Agent: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let displayName = "No Distractions"
    private static let fade: TimeInterval = 0.35

    private var windows: [DesktopWindow] = []
    private var settings = Settings()
    private var statusItem: NSStatusItem?
    private var port: CFMessagePort?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon, never steals focus

        guard let port = Control.Server.start({ [weak self] command in
            self?.handle(command) ?? Reply(ok: false, message: "agent is shutting down")
        }) else {
            fail("another \(Agent.displayName) agent already owns \(Control.portName)")
        }
        self.port = port

        settings = State.load()
        rebuildWindows()
        installStatusItem()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        print("\(Agent.displayName) running — \(statusLine)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let port { CFMessagePortInvalidate(port) }
    }

    // MARK: - Applying

    private var statusLine: String {
        let state = settings.enabled ? "enabled" : "showing real wallpaper"
        return "\(settings.background.summary) [\(state)] on \(windows.count) screen(s)"
    }

    private func apply(fade: TimeInterval = Agent.fade, persist: Bool = true) {
        let background = settings.effectiveBackground
        for window in windows { window.apply(background, fade: fade) }
        if persist { State.save(settings) }
    }

    /// Display reconfiguration is rare, so drop every window and re-create from
    /// the current screen list rather than diffing screen identities.
    private func rebuildWindows() {
        for window in windows { window.orderOut(nil) }
        windows = NSScreen.screens.map(DesktopWindow.init(screen:))
        apply(fade: 0, persist: false)
    }

    @objc private func screensChanged() { rebuildWindows() }

    /// Enabling with nothing chosen would look broken, so fall back to a preset.
    private func setEnabled(_ enabled: Bool, fade: TimeInterval = Agent.fade) {
        settings.enabled = enabled
        if enabled, settings.background == .clear {
            settings.background = .default
        }
        apply(fade: fade)
    }

    private func choose(_ background: Background, fade: TimeInterval = Agent.fade) {
        settings.background = background
        settings.enabled = true
        apply(fade: fade)
    }

    // MARK: - Commands

    private func handle(_ command: Command) -> Reply {
        switch command.kind {
        case .set:
            guard let requested = command.background else {
                return Reply(ok: false, message: "set without a background")
            }
            let validated: Background
            do {
                validated = try requested.validated()
            } catch {
                return Reply(ok: false, message: error.localizedDescription)
            }
            if case .image(let path, let fit) = validated {
                settings.remember(path)
                settings.fit = fit
            }
            choose(validated, fade: command.fade ?? Agent.fade)
            return Reply(ok: true, message: statusLine)

        case .add:
            // Reply first: runModal blocks the main queue, and the IPC handler
            // is dispatched on it.
            DispatchQueue.main.async { self.addImage() }
            return Reply(ok: true, message: "image picker opened")

        case .enable, .disable, .toggle:
            setEnabled(command.kind == .enable ? true
                     : command.kind == .disable ? false
                     : !settings.enabled,
                       fade: command.fade ?? Agent.fade)
            return Reply(ok: true, message: statusLine)

        case .wallpaper:
            guard let path = command.path else {
                return Reply(ok: false, message: "wallpaper without a path")
            }
            do {
                try Wallpaper.set(URL(fileURLWithPath: path))
                return Reply(ok: true, message: "desktop picture set to \(path)")
            } catch {
                return Reply(ok: false, message: error.localizedDescription)
            }

        case .status:
            let screens = windows.map { window in
                let frame = window.frame
                return "\(Int(frame.width))x\(Int(frame.height))@\(Int(frame.minX)),\(Int(frame.minY))"
            }
            return Reply(ok: true, message: """
                \(statusLine)
                window level: \(DesktopWindow.level.rawValue) \
                (wallpaper \(CGWindowLevelForKey(.desktopWindow) - 1), \
                icons \(CGWindowLevelForKey(.desktopIconWindow)))
                screens: \(screens.joined(separator: ", "))
                menu bar item: \(statusItemDiagnostic)
                gradients: \(GradientPreset.all.map(\.id).joined(separator: ", "))
                library: \(settings.library.isEmpty ? "empty" : settings.library.joined(separator: ", "))
                real wallpaper: \(Wallpaper.urls().joined(separator: ", "))
                """)

        case .quit:
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return Reply(ok: true, message: "quitting")
        }
    }

    // MARK: - Menu bar

    /// Enough detail to tell "item missing" from "item pushed off a crowded menu bar".
    private var statusItemDiagnostic: String {
        guard let item = statusItem, let button = item.button else { return "MISSING" }
        let window = button.window
        let onScreen = window?.convertToScreen(button.convert(button.bounds, to: nil)) ?? .zero
        return "visible=\(item.isVisible) length=\(item.length) "
            + "image=\(button.image == nil ? "nil" : "ok") "
            + "button=\(Int(onScreen.width))x\(Int(onScreen.height))@\(Int(onScreen.minX)),\(Int(onScreen.minY)) "
            + "hostWindow=\(window.map { "\(Int($0.frame.width))x\(Int($0.frame.height))@\(Int($0.frame.minX)),\(Int($0.frame.minY))" } ?? "nil")"
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let symbol = NSImage(systemSymbolName: "moon.stars", accessibilityDescription: Agent.displayName)
            symbol?.isTemplate = true
            button.image = symbol
            button.imagePosition = .imageOnly
            if symbol == nil { // no SF Symbol: fall back to text so the item is never 0pt wide
                button.title = "ND"
                button.imagePosition = .noImage
            }
            button.toolTip = Agent.displayName
        }
        let menu = NSMenu()
        menu.delegate = self // rebuilt on every open, so it can never go stale
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // One switch: checked = our background, unchecked = the real wallpaper.
        // Unchecking keeps whichever background is selected below.
        let toggle = add(to: menu, "Enable", #selector(toggleEnabled))
        toggle.state = settings.enabled ? .on : .off

        menu.addItem(.separator())
        menu.setSubmenu(gradientsMenu(), for: add(to: menu, "Gradients", nil))

        menu.setSubmenu(imagesMenu(), for: add(to: menu, "Images", nil))

        menu.addItem(.separator())
        menu.setSubmenu(settingsMenu(), for: add(to: menu, "Settings", nil))
        menu.addItem(.separator())
        add(to: menu, "Quit \(Agent.displayName)", #selector(quit), key: "q")
    }

    private func gradientsMenu() -> NSMenu {
        let menu = NSMenu()
        for preset in GradientPreset.all {
            let item = add(to: menu, preset.title, #selector(choosePreset(_:)))
            item.representedObject = preset.id
            radio(item, on: settings.background == .preset(id: preset.id))
        }
        return menu
    }

    private func imagesMenu() -> NSMenu {
        let menu = NSMenu()
        if settings.library.isEmpty {
            add(to: menu, "No Images Yet", nil)
        } else {
            for (index, path) in settings.library.enumerated() {
                let item = add(to: menu, (path as NSString).lastPathComponent,
                               #selector(chooseImage(_:)))
                item.tag = index
                item.toolTip = path
                radio(item, on: currentImagePath == path)
            }
        }
        menu.addItem(.separator())
        add(to: menu, "Add New Image…", #selector(addImage), key: "o")
        return menu
    }

    private func settingsMenu() -> NSMenu {
        let menu = NSMenu()
        let fit = NSMenu()
        for mode in [Fit.cover, .contain, .stretch, .center] {
            let item = add(to: fit, mode.rawValue.capitalized, #selector(chooseFit(_:)))
            item.representedObject = mode.rawValue
            radio(item, on: settings.fit == mode)
        }
        menu.setSubmenu(fit, for: add(to: menu, "Image Fit", nil))

        menu.addItem(.separator())
        let forget = add(to: menu, "Remove Current Image from List", #selector(forgetCurrentImage))
        forget.isEnabled = currentImagePath != nil
        return menu
    }

    /// `NSMenuItem` with `nil` action renders as a disabled label or a submenu host.
    @discardableResult
    private func add(to menu: NSMenu, _ title: String, _ action: Selector?, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = action == nil ? nil : self
        menu.addItem(item)
        return item
    }

    /// AppKit has no radio menu item, so swap the state images for circles.
    private func radio(_ item: NSMenuItem, on: Bool) {
        item.onStateImage = NSImage(systemSymbolName: "largecircle.fill.circle",
                                    accessibilityDescription: "selected")
        item.offStateImage = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
        item.state = on ? .on : .off
    }

    private var currentImagePath: String? {
        if case .image(let path, _) = settings.background { return path }
        return nil
    }

    // MARK: - Menu actions

    @objc private func toggleEnabled() { setEnabled(!settings.enabled) }

    @objc private func choosePreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        choose(.preset(id: id))
    }

    @objc private func chooseImage(_ sender: NSMenuItem) {
        guard settings.library.indices.contains(sender.tag) else { return }
        choose(.image(path: settings.library[sender.tag], fit: settings.fit))
    }

    @objc private func chooseFit(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let fit = Fit(rawValue: raw) else { return }
        settings.fit = fit
        if let path = currentImagePath {
            choose(.image(path: path, fit: fit), fade: 0)
        } else {
            apply(fade: 0)
        }
    }

    @objc private func addImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Use Image"
        panel.message = "Pick images to cover the desktop wallpaper."

        NSApp.activate() // an accessory app must ask for focus before a modal panel
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        for url in panel.urls.reversed() { settings.remember(url.path) }
        choose(.image(path: panel.urls[0].path, fit: settings.fit))
    }

    @objc private func forgetCurrentImage() {
        guard let path = currentImagePath else { return }
        settings.library.removeAll { $0 == path }
        if let next = settings.library.first {
            choose(.image(path: next, fit: settings.fit))
        } else {
            choose(.default)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
