#!/usr/bin/env bash
# Revert Fix 3 — Remove pcie_aspm=off from GRUB
set -euo pipefail

GRUB_FILE="/etc/default/grub"

echo "=== Reverting Fix 3 ==="

if ! grep -q "pcie_aspm=off" "$GRUB_FILE"; then
    echo "pcie_aspm=off not found in GRUB config. Nothing to revert."
    exit 0
fi

sed -i 's/ pcie_aspm=off//' "$GRUB_FILE"

echo "Updated GRUB_CMDLINE_LINUX_DEFAULT:"
grep "GRUB_CMDLINE_LINUX_DEFAULT" "$GRUB_FILE"

echo ""
echo "Running update-grub..."
update-grub

echo ""
echo "=== Fix 3 reverted ==="
echo ">>> REBOOT REQUIRED <<<"
