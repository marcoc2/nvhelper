#!/usr/bin/env bash
# Revert Fix 2 — Remove persistence mode override
set -euo pipefail

OVERRIDE_DIR="/etc/systemd/system/nvidia-persistenced.service.d"

echo "=== Reverting Fix 2 ==="

if [ -d "$OVERRIDE_DIR" ]; then
    rm -rf "$OVERRIDE_DIR"
    echo "Removed override directory."
else
    echo "No override found — nothing to revert."
fi

systemctl daemon-reload
systemctl restart nvidia-persistenced.service

nvidia-smi -pm 0 2>/dev/null || true

echo ""
echo "=== Fix 2 reverted ==="
