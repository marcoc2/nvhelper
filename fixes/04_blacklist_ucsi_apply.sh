#!/usr/bin/env bash
# Fix 4 — Blacklist ucsi_acpi to stop the connector-change CPU hog on dock connect
# Confidence: MEDIUM — matches widely reported UCSI_GET_PDOS(-5) quirk on this class
#             of Intel USB-C controller; community-reported workaround, not an
#             NVIDIA/Dell-confirmed fix.
# Requires: sudo + reboot
#
# Risk: ucsi_acpi also handles USB-C power role / PD negotiation reporting.
# Blacklisting it can affect dock charging behavior or USB-C role switching
# on some hardware. After applying and rebooting, dock the laptop and verify:
#   - external monitor comes up
#   - laptop charges through the dock
#   - no new gnome-session-failed entries after connecting
# If charging or role negotiation breaks, run 04_blacklist_ucsi_revert.sh.

set -euo pipefail

CONF="/etc/modprobe.d/blacklist-ucsi-acpi.conf"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"
mkdir -p "$BACKUP_DIR"

echo "=== Fix 4: Blacklist ucsi_acpi ==="

if [ -f "$CONF" ]; then
    cp "$CONF" "$BACKUP_DIR/blacklist-ucsi-acpi.conf.bak.$(date +%Y%m%d_%H%M%S)"
    echo "Existing config backed up."
fi

cat > "$CONF" << 'EOF'
# Blocks the ucsi_acpi USB-C connector-change handler, which was observed
# hogging the CPU (workqueue: ucsi_handle_connector_change hogged CPU for
# >10000us) while docking, long enough for gnome-session to declare the
# session failed and force a relogin.
blacklist ucsi_acpi
EOF

echo "Created $CONF"
cat "$CONF"

echo ""
echo "Rebuilding initramfs..."
update-initramfs -u

echo ""
echo "=== Fix 4 applied ==="
echo ">>> REBOOT REQUIRED <<<"
echo "After reboot, dock the laptop and verify:"
echo "  - external monitor works"
echo "  - laptop charges through the dock"
echo "  - dmesg | grep ucsi   -> should show nothing new"
echo "  - journalctl -b -o short-iso --grep='gnome-session-failed'  -> should stay quiet after docking"
