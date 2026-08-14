import AppKit

/// The real macOS desktop picture — what the Dock's wallpaper window draws,
/// two levels below our overlay. We can only replace its content: the window
/// itself belongs to another process, and cross-process window manipulation
/// needs private SkyLight calls that macOS blocks.
enum Wallpaper {
    static func urls() -> [String] {
        NSScreen.screens.map { NSWorkspace.shared.desktopImageURL(for: $0)?.path ?? "" }
    }

    static func set(_ url: URL) throws {
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }
}
