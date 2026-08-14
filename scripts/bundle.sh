#!/bin/sh
# Builds "dist/No Distractions.app" — a LSUIElement (menu-bar-only) wrapper
# around the same binary.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/dist/No Distractions.app"
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
lipo -create -output "$macos/nodistractions" \
	"$root/.build/arm64-apple-macosx/release/nodistractions" \
	"$root/.build/x86_64-apple-macosx/release/nodistractions"

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
	<key>CFBundleName</key><string>No Distractions</string>
	<key>CFBundleDisplayName</key><string>No Distractions</string>
	<key>CFBundleIdentifier</key><string>dev.nodistractions.app</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleIconName</key><string>AppIcon</string>
	<key>CFBundleExecutable</key><string>nodistractions</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

# SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" produces a signature
# Gatekeeper accepts once the app is also notarised. Notarisation *requires* the
# hardened runtime and a secure timestamp, so both go on here rather than in CI.
# Without it, fall back to an ad-hoc signature: runnable, but quarantined on
# other machines.
identity="${SIGN_IDENTITY:--}"
if [ "$identity" = "-" ]; then
	codesign --force --sign - "$app"
	echo "note: ad-hoc signed — downloads will be quarantined" >&2
else
	codesign --force --timestamp --options runtime --sign "$identity" "$app"
fi
codesign --verify --strict --verbose=1 "$app"
lipo -info "$macos/nodistractions"

echo "built $app"
echo "  open \"$app\"                       # menu-bar agent, no Dock icon"
echo "  .build/release/nodistractions status  # or symlink it onto your PATH"
