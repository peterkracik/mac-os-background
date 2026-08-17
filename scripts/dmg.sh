#!/bin/sh
# Builds "dist/NoDistractions.dmg" — the classic drag-and-drop installer.
# Opening it shows the app beside an Applications symlink over a backdrop
# whose arrow points the way. Finder keeps that layout (icon positions,
# window size, background picture) in the volume's .DS_Store, and Finder is
# the only tool that writes that format sensibly — so a read-write image is
# mounted, Finder is scripted into shape, and the result is compressed.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/dist/No Distractions.app"
dmg="$root/dist/NoDistractions.dmg"
background="$root/Resources/DMGBackground.tiff"

[ -d "$app" ] || sh "$root/scripts/bundle.sh"
[ -f "$background" ] || (cd "$root" && swift scripts/make-dmg-background.swift)

work=$(mktemp -d)
staging="$work/No Distractions"
trap 'rm -rf "$work"' EXIT
mkdir -p "$staging/.background"
cp -R "$app" "$staging/"
cp "$background" "$staging/.background/background.tiff"
cp "$root/Resources/AppIcon.icns" "$staging/.VolumeIcon.icns"
ln -s /Applications "$staging/Applications"

# Headroom over the payload so Finder can write its metadata.
size=$(( $(du -sm "$staging" | cut -f1) + 10 ))
hdiutil create -srcfolder "$staging" -volname "No Distractions" -fs HFS+ \
	-format UDRW -size "${size}m" -ov "$work/rw.dmg" > /dev/null

# Browsable mount (no -nobrowse): Finder can only script disks it can see.
attached=$(hdiutil attach "$work/rw.dmg" -readwrite -noverify -noautoopen | grep /Volumes/)
device=$(printf '%s' "$attached" | cut -f1 | tr -d '[:space:]')
mount=$(printf '%s' "$attached" | sed 's|.*\(/Volumes/.*\)|\1|')
trap 'hdiutil detach "$device" -force > /dev/null 2>&1 || true; rm -rf "$work"' EXIT

# Window bounds are 660x428 so the content area under the title bar matches
# the 660x400 background; both icon centres sit on its y = 185 arrow line.
style() {
	osascript <<-EOF
	tell application "Finder"
		tell disk "$(basename "$mount")"
			open
			delay 1
			set current view of container window to icon view
			set toolbar visible of container window to false
			set statusbar visible of container window to false
			set the bounds of container window to {200, 120, 860, 548}
			set viewOptions to the icon view options of container window
			set arrangement of viewOptions to not arranged
			set icon size of viewOptions to 128
			set text size of viewOptions to 13
			set background picture of viewOptions to file ".background:background.tiff"
			set position of item "No Distractions.app" of container window to {165, 185}
			set position of item "Applications" of container window to {495, 185}
			close
			open
			update without registering applications
			delay 1
			close
		end tell
	end tell
	EOF
}

# A busy machine can refuse the first Apple event; retry before failing loudly.
attempt=1
until style; do
	attempt=$((attempt + 1))
	if [ "$attempt" -gt 3 ]; then
		echo "nodistractions: Finder refused to style the volume" >&2
		exit 1
	fi
	echo "retrying Finder styling ($attempt/3)" >&2
	sleep 4
done

# The custom-icon bit makes .VolumeIcon.icns take effect. Purely cosmetic, so
# a toolchain without SetFile just keeps the stock disk icon.
xcrun SetFile -a C "$mount" 2> /dev/null \
	|| echo "note: SetFile unavailable — volume keeps the stock icon" >&2

# Finder writes .DS_Store asynchronously; wait for it rather than hope.
tries=0
until [ -f "$mount/.DS_Store" ]; do
	tries=$((tries + 1))
	if [ "$tries" -gt 10 ]; then
		echo "nodistractions: Finder never wrote $mount/.DS_Store" >&2
		exit 1
	fi
	sleep 1
done
sync

tries=0
until hdiutil detach "$device" > /dev/null 2>&1; do
	tries=$((tries + 1))
	if [ "$tries" -gt 5 ]; then
		echo "nodistractions: could not detach $device" >&2
		exit 1
	fi
	sleep 2
done
trap 'rm -rf "$work"' EXIT

rm -f "$dmg"
hdiutil convert "$work/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$dmg" > /dev/null

# Same contract as bundle.sh: SIGN_IDENTITY signs the image, unset ships it as is.
identity="${SIGN_IDENTITY:--}"
[ "$identity" = "-" ] || codesign --force --timestamp --sign "$identity" "$dmg"

echo "built $dmg"
echo "  open \"$dmg\"   # drag No Distractions onto Applications"
