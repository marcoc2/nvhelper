#!/usr/bin/env bash
# Fix 2 — Enable persistence mode on nvidia-persistenced
# Confidence: MEDIUM — keeps driver loaded, avoids modprobe cycling
# Requires: sudo, NO reboot needed

set -euo pipefail

OVERRIDE_DIR="/etc/systemd/system/nvidia-persistenced.service.d"
mkdir -p "$OVERRIDE_DIR"

echo "=== Fix 2: Enable Persistence Mode ==="

# Create systemd override to remove --no-persistence-mode
cat > "$OVERRIDE_DIR/override.conf" << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/nvidia-persistenced --user nvidia-persistenced --verbose
EOF

echo "Created systemd override: $OVERRIDE_DIR/override.conf"

# Reload and restart
systemctl daemon-reload
systemctl restart nvidia-persistenced.service

# Set persistence mode immediately
echo ""
echo "Setting persistence mode via nvidia-smi..."
nvidia-smi -pm 1

echo ""
echo "=== Fix 2 applied ==="
echo "Verification:"
nvidia-smi -q | grep -A1 "Persistence Mode" || true
echo ""
echo "No reboot required."
