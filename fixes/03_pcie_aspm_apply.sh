#!/usr/bin/env bash
# Fix 3 — Disable PCIe ASPM via GRUB
# Confidence: LOW — fallback if fixes 1+2 are insufficient
# Requires: sudo + reboot

set -euo pipefail

GRUB_FILE="/etc/default/grub"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"
mkdir -p "$BACKUP_DIR"

echo "=== Fix 3: Disable PCIe ASPM ==="

# Backup GRUB config
cp "$GRUB_FILE" "$BACKUP_DIR/grub.bak.$(date +%Y%m%d_%H%M%S)"
echo "GRUB config backed up."

# Check if already present
if grep -q "pcie_aspm=off" "$GRUB_FILE"; then
    echo "pcie_aspm=off already present in GRUB config. Nothing to do."
    exit 0
fi

# Append to GRUB_CMDLINE_LINUX_DEFAULT
sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)/\1 pcie_aspm=off/' "$GRUB_FILE"

echo "Updated GRUB_CMDLINE_LINUX_DEFAULT:"
grep "GRUB_CMDLINE_LINUX_DEFAULT" "$GRUB_FILE"

echo ""
echo "Running update-grub..."
update-grub

echo ""
echo "=== Fix 3 applied ==="
echo ">>> REBOOT REQUIRED <<<"
echo "After reboot, verify:"
echo "  dmesg | grep -i aspm"
echo "  cat /proc/cmdline | grep pcie_aspm"
