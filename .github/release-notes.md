Menu-bar app that covers the macOS desktop wallpaper while leaving the desktop
icons visible and clickable.

## Install

1. Download `descreet.zip` below and unzip it.
2. Move **descreet.app** into `/Applications`.
3. The build is ad-hoc signed and not notarised, so macOS quarantines it. Clear
   that once:

   ```sh
   xattr -dr com.apple.quarantine "/Applications/descreet.app"
   ```

   (Or: right-click the app, choose Open, then Open again. On macOS 15+ you may
   need System Settings → Privacy & Security → Open Anyway.)
4. Open it. A moon appears in the menu bar; there is no Dock icon.

## Using it

- **Enable** — toggle between the overlay and your real wallpaper. Unchecking
  keeps whatever background you picked.
- **Gradients ▸** — five built-in gradients; Aqua is the default.
- **Images ▸** — your added images, with **Add New Image…** at the bottom.
- **Settings ▸ Image Fit** — cover, contain, stretch, center.

The overlay sits on `kCGDesktopWindowLevel`: above the wallpaper, twenty levels
below Finder's icon window, and click-through, so icons stay usable.

Universal binary (Apple silicon + Intel). Requires macOS 14 or later.
