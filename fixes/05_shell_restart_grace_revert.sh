#!/usr/bin/env bash
# Revert Fix 5 — Remove the gnome-shell restart grace drop-in
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "Run as the desktop user, not root: this is a systemd --user drop-in." >&2
    exit 1
fi

UNIT="org.gnome.Shell@x11.service"
DROPIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$UNIT.d"
CONF="$DROPIN_DIR/restart-grace.conf"

echo "=== Reverting Fix 5 ==="

if [ ! -f "$CONF" ]; then
    echo "$CONF not found. Nothing to revert."
    exit 0
fi

rm "$CONF"
echo "Removed $CONF"
rmdir "$DROPIN_DIR" 2>/dev/null || true

systemctl --user daemon-reload

echo ""
echo "Effective settings:"
systemctl --user show "$UNIT" -p RestartUSec -p RestartMode -p StartLimitBurst -p StartLimitIntervalUSec

echo ""
echo "=== Fix 5 reverted (no reboot needed) ==="
