#!/usr/bin/env bash
# focus-timer-kde-dnd installer (user-level, Arch Linux friendly)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
UNIT_DIR="$HOME/.config/systemd/user"
STATE_DIR="$HOME/.local/state/focus-dnd"
CONFIG_DIR="$HOME/.config"

echo "==> Focus Timer ↔ KDE Plasma DND installer"
echo "This will install files to user directories and enable a systemd user service."
echo "  bin:  $BIN_DIR"
echo "  unit: $UNIT_DIR/focus-dnd.service"
echo "  state: $STATE_DIR"
echo

# Prerequisites
missing=()
for cmd in python3 systemctl; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if ! command -v qdbus6 >/dev/null 2>&1 && ! command -v qdbus >/dev/null 2>&1; then
  missing+=("qdbus6/qdbus")
fi
if ! command -v flock >/dev/null 2>&1; then
  missing+=("flock (util-linux)")
fi

if [ ${#missing[@]} -gt 0 ]; then
  echo "ERROR: Missing required commands: ${missing[*]}"
  echo "On Arch: sudo pacman -S python python-gobject qt6-tools util-linux"
  exit 1
fi

echo "==> Prerequisites OK"
mkdir -p "$BIN_DIR" "$UNIT_DIR" "$STATE_DIR"

# Install binaries
for f in focus-dnd-service focus-dnd-on focus-dnd-off; do
  src="$SCRIPT_DIR/bin/$f"
  dst="$BIN_DIR/$f"
  if [ -f "$dst" ]; then
    bak="$dst.bak-$(date +%Y%m%d-%H%M%S)"
    echo "  Backing up existing $dst -> $bak"
    cp -p "$dst" "$bak"
  fi
  echo "  Installing $f -> $dst"
  install -m 755 "$src" "$dst"
done

# Install unit
src_unit="$SCRIPT_DIR/systemd/focus-dnd.service"
dst_unit="$UNIT_DIR/focus-dnd.service"
if [ -f "$dst_unit" ]; then
  bak="$dst_unit.bak-$(date +%Y%m%d-%H%M%S)"
  echo "  Backing up existing $dst_unit -> $bak"
  cp -p "$dst_unit" "$bak"
fi
echo "  Installing unit -> $dst_unit"
install -m 644 "$src_unit" "$dst_unit"

# Reload and enable/start
echo "==> Enabling and starting service (user)"
systemctl --user daemon-reload
systemctl --user enable --now focus-dnd.service || true

echo
echo "==> Installation complete"
echo "Check status: systemctl --user status focus-dnd.service"
echo "Check state:  qdbus6 io.github.haykay.FocusDND /io/github/haykay/FocusDND io.github.haykay.FocusDND.GetState"
echo "Logs:         journalctl --user -u focus-dnd.service -n 20"
