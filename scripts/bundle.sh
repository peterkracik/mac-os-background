#!/bin/sh
# Builds "dist/descreet.app" — a LSUIElement (menu-bar-only) wrapper
# around the same binary.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/dist/descreet.app"
macos="$app/Contents/MacOS"
resources="$app/Contents/Resources"

# Universal binary. `swift build --arch arm64 --arch x86_64` needs full Xcode
# (xcbuild), so each slice is built by triple and merged with lipo, which works
# with the Command Line Tools alone.
for triple in arm64-apple-macosx14.0 x86_64-apple-macosx14.0; do
	swift build -c release --triple "$triple" --package-path "$root"
done

rm -rf "$app"
mkdir -p "$macos" "$resources"
lipo -create -output "$macos/descreet" \
	"$root/.build/arm64-apple-macosx/release/descreet" \
	"$root/.build/x86_64-apple-macosx/release/descreet"

# The icon is generated from the same colours as the Aqua preset.
[ -f "$root/Resources/AppIcon.icns" ] || (cd "$root" && swift scripts/make-icon.swift)
cp "$root/Resources/AppIcon.icns" "$resources/AppIcon.icns"

# CFBundleExecutable must be this exact binary: a shim that exec'd a second
# executable left the process without bundle identity, and macOS 26 then
# silently refuses it a menu bar slot. With no arguments the binary detects the
# bundle identifier and starts the agent itself.

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>descreet</string>
	<key>CFBundleDisplayName</key><string>descreet</string>
	<key>CFBundleIdentifier</key><string>dev.descreet.app</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleIconName</key><string>AppIcon</string>
	<key>CFBundleExecutable</key><string>descreet</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough for Gatekeeper's "open anyway" path, not notarised.
codesign --force --deep --sign - "$app"
codesign --verify --strict "$app"
lipo -info "$macos/descreet"

echo "built $app"
echo "  open \"$app\"                       # menu-bar agent, no Dock icon"
echo "  .build/release/descreet status  # or symlink it onto your PATH"
