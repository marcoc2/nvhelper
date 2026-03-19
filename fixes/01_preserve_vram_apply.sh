#!/usr/bin/env bash
# Fix 1 — Enable NVreg_PreserveVideoMemoryAllocations + nvidia_drm.fbdev
# Confidence: HIGH — this is the documented NVIDIA prerequisite for suspend/resume
# Requires: sudo + reboot

set -euo pipefail

CONF="/etc/modprobe.d/nvidia-power-management.conf"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"
mkdir -p "$BACKUP_DIR"

echo "=== Fix 1: PreserveVideoMemoryAllocations + fbdev ==="

# Backup existing config if present
if [ -f "$CONF" ]; then
    cp "$CONF" "$BACKUP_DIR/nvidia-power-management.conf.bak.$(date +%Y%m%d_%H%M%S)"
    echo "Existing config backed up."
fi

# Create modprobe config
cat > "$CONF" << 'EOF'
# NVIDIA power management — preserve VRAM across suspend/resume
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia_drm fbdev=1
EOF

echo "Created $CONF"
cat "$CONF"

# Rebuild initramfs
echo ""
echo "Rebuilding initramfs..."
update-initramfs -u

# Enable systemd suspend/hibernate services
echo ""
echo "Enabling NVIDIA suspend/hibernate services..."
systemctl enable nvidia-suspend.service
systemctl enable nvidia-resume.service
systemctl enable nvidia-hibernate.service
systemctl enable nvidia-suspend-then-hibernate.service 2>/dev/null || true

echo ""
echo "=== Fix 1 applied ==="
echo "Current PreserveVideoMemoryAllocations (before reboot):"
cat /sys/module/nvidia/parameters/PreserveVideoMemoryAllocations 2>/dev/null || echo "[will take effect after reboot]"
echo ""
echo ">>> REBOOT REQUIRED <<<"
echo "After reboot, verify:"
echo "  cat /sys/module/nvidia/parameters/PreserveVideoMemoryAllocations  # should be 1"
