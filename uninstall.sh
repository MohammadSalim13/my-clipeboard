#!/bin/bash
# Quits and removes Clipboard History. Pass --keep-history to keep the saved items.
set -euo pipefail

pkill -x ClipboardHistory 2>/dev/null || true
rm -rf "/Applications/Clipboard History.app"
tccutil reset Accessibility local.ClipboardHistory >/dev/null 2>&1 || true
defaults delete local.ClipboardHistory >/dev/null 2>&1 || true
if [ "${1:-}" != "--keep-history" ]; then
  rm -rf "$HOME/Library/Application Support/Clipboard History"
fi
echo "✔ Removed. (If it still shows in System Settings › General › Login Items, remove it there.)"
