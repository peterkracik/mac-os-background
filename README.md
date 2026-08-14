<div align="center">
<img src="Resources/icon-1024.png" width="128" alt="descreet">
<h1>descreet</h1>
<p>Covers the macOS desktop wallpaper. Leaves the icons alone.</p>
</div>

A menu-bar app that draws a calm gradient (or your own image) over the desktop
wallpaper, without hiding or disabling the desktop icons.

## Install

Download the latest `descreet.zip` from
[Releases](../../releases/latest), unzip, and move **descreet.app** to
`/Applications`.

The build is ad-hoc signed and not notarised — there is no Apple Developer
account behind it — so macOS quarantines the download. Clear it once:

```sh
xattr -dr com.apple.quarantine "/Applications/descreet.app"
```

Then open the app. A moon appears in the menu bar; there is no Dock icon. To
start it at login, add it under System Settings → General → Login Items.

## How it works

macOS composites the desktop in a fixed stack. Measured on macOS 26:

| Layer | Owner | Role |
| --- | --- | --- |
| -2147483601 | Notification Center | desktop widgets |
| -2147483603 | Finder, WindowManager | **desktop icons** |
| **-2147483623** | descreet | **the overlay** |
| -2147483624 | Dock | wallpaper container |
| -2147483625 | Wallpaper | wallpaper renderer |
| -2147483626 | Window Server | display backstop |

`kCGDesktopWindowLevel` (-2147483623) is the one free slot: everything below it
is wallpaper machinery, and Finder's icon window sits twenty levels above. A
borderless, click-through window there hides the wallpaper and nothing else —
icons stay visible, selectable and right-clickable, and every normal window,
Stage Manager and Mission Control are unaffected.

Desktop widgets sit *above* the icons, so they can never be covered by this
approach. That is the hard ceiling on "cover the wallpaper but not the icons".

## Menu

- **Enable** — overlay on, or your real wallpaper. Unchecking keeps your
  selection, so re-enabling restores it.
- **Gradients ▸** — Aqua (default), Midnight, Graphite, Aurora, Dusk. Built from
  code: a multi-stop base plus one soft radial glow.
- **Images ▸** — remembered images, with **Add New Image…** last.
- **Settings ▸ Image Fit** — cover, contain, stretch, center.

## Command line

The same binary inside the bundle is a CLI that talks to the running app over a
Mach port:

```sh
alias nd='/Applications/descreet.app/Contents/MacOS/descreet'

nd set gradient aqua              # built-in preset
nd set gradient '#0b1020' '#4a2b6b' --angle 270
nd set color '#101014'
nd set image ~/Pictures/wall.jpg --fit cover
nd enable | nd disable | nd toggle
nd status                         # what is showing, and at which window level
nd wallpaper ~/Pictures/real.jpg  # set the real desktop picture instead
nd quit
```

`--fade <seconds>` controls the crossfade (default 0.35). Every command
validates input before it reaches the app, and fails loudly if the app is not
running.

State lives in `~/Library/Application Support/descreet/state.json`.

## Build from source

Requires macOS 14+ and a Swift 6 toolchain (Xcode 16 or its Command Line
Tools).

```sh
sh scripts/bundle.sh          # → dist/descreet.app (universal binary)
swift scripts/make-icon.swift # regenerate Resources/AppIcon.icns
swift build -c release        # CLI only
```

`scripts/bundle.sh` builds one slice per architecture and merges them with
`lipo`, because `swift build --arch arm64 --arch x86_64` requires full Xcode.

Tagging `v*` runs `.github/workflows/release.yml`, which builds the universal
bundle and attaches the zip plus its SHA-256 to a GitHub release.
