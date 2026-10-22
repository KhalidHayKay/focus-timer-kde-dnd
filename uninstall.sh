#!/usr/bin/env bash
# focus-timer-kde-dnd uninstaller (user-level, safe)
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
UNIT_DIR="$HOME/.config/systemd/user"
STATE_DIR="$HOME/.local/state/focus-dnd"

echo "==> Focus Timer ↔ KDE Plasma DND uninstaller"
echo "This will stop/disable ONLY this project's service and remove ONLY files it installed."
echo "It will NOT toggle DND, and it will NOT remove your config/logs/backups."
echo

read -p "Proceed? [y/N] " -n 1 -r
echo
[[ $REPLY =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# Stop and disable service
if systemctl --user is-active --quiet focus-dnd.service 2>/dev/null; then
  echo "==> Stopping focus-dnd.service"
  systemctl --user stop focus-dnd.service || true
fi
if systemctl --user is-enabled --quiet focus-dnd.service 2>/dev/null; then
  echo "==> Disabling focus-dnd.service"
  systemctl --user disable focus-dnd.service || true
fi

# Remove only project files (don't touch backups)
for f in focus-dnd-service focus-dnd-on focus-dnd-off; do
  dst="$BIN_DIR/$f"
  if [ -f "$dst" ]; then
    echo "  Removing $dst"
    rm -f "$dst"
  fi
done

dst_unit="$UNIT_DIR/focus-dnd.service"
if [ -f "$dst_unit" ]; then
  echo "  Removing $dst_unit"
  rm -f "$dst_unit"
fi

systemctl --user daemon-reload || true

echo
echo "==> Uninstallation complete"
echo "Left behind: $STATE_DIR/ (logs/state), ~/.config/plasmanotifyrc, all *.bak files"
echo "DND state was not changed."
