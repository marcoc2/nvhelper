#!/usr/bin/env bash
# Revert Fix 1 — Remove VRAM preservation config
set -euo pipefail

CONF="/etc/modprobe.d/nvidia-power-management.conf"

echo "=== Reverting Fix 1 ==="

if [ -f "$CONF" ]; then
    rm "$CONF"
    echo "Removed $CONF"
else
    echo "$CONF not found — nothing to revert."
fi

echo "Rebuilding initramfs..."
update-initramfs -u

echo ""
echo "=== Fix 1 reverted ==="
echo ">>> REBOOT REQUIRED <<<"
