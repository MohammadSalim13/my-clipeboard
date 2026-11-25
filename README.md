# Clipboard History

A small menu bar app for macOS that works like Windows' clipboard history (Win+V).

- **⌘C** copies as usual. Everything you copy (text, links, images, files, rich text) is saved.
- **⌥V (Option-V)** opens the list next to your text cursor. Pick an item and it gets pasted into the app you were using.
- Starts automatically when you log in.

## Install

```bash
./install.sh
```

This builds the app for Intel (`x86_64`), copies it to `/Applications/Clipboard History.app` and starts it.
A clipboard icon appears in the menu bar.

**One-time setup:** macOS asks to allow *Clipboard History* under
**System Settings › Privacy & Security › Accessibility**. Turn it on. The app needs this to press ⌘V for
you (auto-paste) and to find your text cursor. Without it, choosing an item still copies it, and you press ⌘V yourself.

For Apple silicon, build with `ARCH=arm64 ./install.sh`.

## Using the list

| Key | Action |
| --- | --- |
| ⌥V | Open / close the list |
| ↑ ↓ | Move the selection |
| ↩ or click | Paste the selected item |
| ⌘1 – ⌘9 | Paste item 1–9 right away |
| type | Search |
| ⌘P | Pin / unpin. Pinned items survive "Clear all" and the 50-item limit. |
| ⌘⌫ | Delete the selected item |
| Esc | Clear the search, then close |

Right-click an item for Paste / Pin / Delete.

The menu bar icon has: *Paste Automatically After Choosing*, *Open at Login*, *Clear History*, *Quit*.

## Notes

- History is saved in `~/Library/Application Support/Clipboard History/history.plist` (readable only by you).
  Copies that password managers mark as secret are not recorded.
- Up to 50 unpinned items are kept. Very large items (over 25 MB) keep only their text or a PNG version.
- ⌥V normally types `√`. While the app runs, it opens the history instead.
- The app is signed locally (ad-hoc), so each rebuild counts as a new app to macOS.
  `install.sh` resets the old Accessibility entry, so after reinstalling, turn the permission on again.

## Uninstall

```bash
./uninstall.sh            # removes the app and its history
./uninstall.sh --keep-history
```

## Project layout

```
Sources/main.swift            app entry
Sources/AppDelegate.swift     menu bar icon, hotkey, pasting
Sources/ClipboardStore.swift  reading/saving clipboard items, history file
Sources/HistoryPanel.swift    the ⌥V popup (search, list, keyboard handling)
Sources/System.swift          global hotkey, auto-paste, cursor position, start at login
scripts/make_icon.swift       draws the app icon
build.sh / install.sh / uninstall.sh
```
