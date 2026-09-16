#!/usr/bin/env bash
# Revert Fix 4 — Remove ucsi_acpi blacklist
set -euo pipefail

CONF="/etc/modprobe.d/blacklist-ucsi-acpi.conf"

echo "=== Reverting Fix 4 ==="

if [ ! -f "$CONF" ]; then
    echo "$CONF not found. Nothing to revert."
    exit 0
fi

rm "$CONF"
echo "Removed $CONF"

echo ""
echo "Rebuilding initramfs..."
update-initramfs -u

echo ""
echo "=== Fix 4 reverted ==="
echo ">>> REBOOT REQUIRED <<<"
