## Install

1. Download `NoDistractions.dmg` below and open it.
2. Drag **No Distractions** onto the **Applications** folder, the way the
   arrow shows, then eject the image.
3. This build is ad-hoc signed and **not** notarised, so macOS quarantines it.
   Clear that once:

   ```sh
   xattr -dr com.apple.quarantine "/Applications/No Distractions.app"
   ```

   (Or right-click the app → Open, then confirm. On macOS 15+ you may also need
   System Settings → Privacy & Security → Open Anyway.)
4. Open it. A moon appears in the menu bar; there is no Dock icon.

To start it at login, turn on **Settings ▸ Start at Login** in the moon menu.
(macOS may ask you to approve it under System Settings → Login Items.)

