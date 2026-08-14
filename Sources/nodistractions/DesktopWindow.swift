import AppKit

/// A borderless, click-through window pinned to the wallpaper layer of one screen.
///
/// Level math (verified on macOS 26): the wallpaper itself is composited at
/// `kCGDesktopWindowLevel - 1` and below, while Finder draws desktop icons at
/// `kCGDesktopIconWindowLevel` (= desktop + 20). Sitting exactly on
/// `kCGDesktopWindowLevel` therefore hides the wallpaper and nothing else —
/// icons, Stage Manager and every normal window stay on top.
final class DesktopWindow: NSWindow {
    static let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

    private let view = BackgroundView()
    private let assignedScreen: NSScreen

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen) {
        assignedScreen = screen
        super.init(contentRect: screen.frame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)
        level = DesktopWindow.level
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true // clicks reach the Finder desktop underneath
        isReleasedWhenClosed = false
        canHide = false
        animationBehavior = .none
        contentView = view
        setFrame(screen.frame, display: false)
        orderFrontRegardless() // the app never activates, so plain orderFront is a no-op
    }

    func apply(_ background: Background, fade: TimeInterval) {
        view.apply(background, scale: assignedScreen.backingScaleFactor, fade: fade)
    }
}

/// Hosts at most one content layer, crossfading when it is replaced.
private final class BackgroundView: NSView {
    private var current: CALayer?

    override var isOpaque: Bool { false }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    func apply(_ background: Background, scale: CGFloat, fade: TimeInterval) {
        let host = layer!
        let next = background.makeLayer(scale: scale)
        let previous = current
        current = next

        if let next {
            resize(next)
            next.opacity = fade > 0 ? 0 : 1
            host.addSublayer(next)
        }

        guard fade > 0 else {
            previous?.removeFromSuperlayer()
            return
        }

        // The incoming layer fades up over the outgoing one (or over the real
        // wallpaper); the outgoing one fades down so disabling reveals gradually.
        CATransaction.begin()
        CATransaction.setAnimationDuration(fade)
        CATransaction.setCompletionBlock { previous?.removeFromSuperlayer() }
        next?.opacity = 1
        previous?.opacity = 0
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.sublayers?.forEach(resize)
        CATransaction.commit()
    }

    /// Presets nest a base gradient plus a glow, so every descendant is screen-sized.
    private func resize(_ layer: CALayer) {
        layer.frame = bounds
        layer.sublayers?.forEach(resize)
    }
}
