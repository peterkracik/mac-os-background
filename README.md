<div align="center">
<img src="Resources/icon-1024.png" width="120" alt="No Distractions">
<h1>No Distractions</h1>
</div>

**Because sometimes it is needed …**

A quiet gradient over your desktop wallpaper. Your icons stay exactly where they
are — still visible, still clickable.

## Install

1. Download `NoDistractions.dmg` from [Releases](../../releases/latest).
2. Open it and drag **No Distractions** onto **Applications** — the window
   shows the way. (Prefer an archive? `NoDistractions.zip` is there too.)
3. Open the app. A moon appears in the menu bar — there's no Dock icon.

Signed and notarised by Apple, so it just opens. To have it start with your Mac:
click the moon and turn on **Settings ▸ Start at Login**.

## Use it

Click the moon:

- **Enable** — overlay on, or your real wallpaper back. Your choice is remembered.
- **Gradients ▸** — Aqua, Midnight, Graphite, Aurora, Dusk.
- **Images ▸** — your own pictures, with **Add New Image…** at the bottom.
- **Settings ▸ Image Fit** — cover, contain, stretch, center.
- **Settings ▸ Start at Login** — open automatically when you log in.

## Build it yourself

```sh
sh scripts/bundle.sh   # → dist/No Distractions.app
sh scripts/dmg.sh      # → dist/NoDistractions.dmg, the drag-and-drop installer
```

Needs macOS 14+ and a Swift 6 toolchain. Tagging `v*` builds and publishes a
release.

<details>
<summary>How it stays under the icons</summary>

macOS draws the wallpaper below `kCGDesktopWindowLevel` and Finder's icons twenty
levels above it, so a borderless click-through window sits in between: wallpaper
hidden, everything else untouched. Desktop widgets live above the icons, so those
can never be covered.

</details>
