#!/usr/bin/env bash
# diagnose.sh — Capture a full NVIDIA GPU state snapshot
# Usage: sudo ./diagnose.sh <label>
# Example: sudo ./diagnose.sh pre-suspend

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIAG_DIR="$SCRIPT_DIR/diagnostics"
mkdir -p "$DIAG_DIR"

LABEL="${1:-snapshot}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTFILE="$DIAG_DIR/${LABEL}_${TIMESTAMP}.log"

section() {
    echo "===== $1 =====" >> "$OUTFILE"
    echo "" >> "$OUTFILE"
}

run_cmd() {
    local desc="$1"
    shift
    section "$desc"
    if "$@" >> "$OUTFILE" 2>&1; then
        echo "" >> "$OUTFILE"
    else
        echo "[FAILED - exit code $?]" >> "$OUTFILE"
        echo "" >> "$OUTFILE"
    fi
}

echo "GPU Diagnostic Snapshot — $LABEL" > "$OUTFILE"
echo "Timestamp: $(date)" >> "$OUTFILE"
echo "Kernel: $(uname -r)" >> "$OUTFILE"
echo "" >> "$OUTFILE"

# nvidia-smi
run_cmd "nvidia-smi" nvidia-smi
run_cmd "nvidia-smi -q (detailed query)" nvidia-smi -q

# Loaded NVIDIA kernel modules
section "NVIDIA kernel modules"
lsmod | grep -i nvidia >> "$OUTFILE" 2>&1 || echo "[none loaded]" >> "$OUTFILE"
echo "" >> "$OUTFILE"

# nvidia module parameters
section "nvidia module parameters"
if [ -d /sys/module/nvidia/parameters ]; then
    for param in /sys/module/nvidia/parameters/*; do
        name="$(basename "$param")"
        val="$(cat "$param" 2>/dev/null || echo '[unreadable]')"
        echo "  $name = $val" >> "$OUTFILE"
    done
else
    echo "[nvidia module not loaded]" >> "$OUTFILE"
fi
echo "" >> "$OUTFILE"

# nvidia_drm module parameters
section "nvidia_drm module parameters"
if [ -d /sys/module/nvidia_drm/parameters ]; then
    for param in /sys/module/nvidia_drm/parameters/*; do
        name="$(basename "$param")"
        val="$(cat "$param" 2>/dev/null || echo '[unreadable]')"
        echo "  $name = $val" >> "$OUTFILE"
    done
else
    echo "[nvidia_drm module not loaded]" >> "$OUTFILE"
fi
echo "" >> "$OUTFILE"

# PCIe link status for NVIDIA devices
section "PCIe link status (NVIDIA devices)"
lspci -vv -d 10de: 2>> "$OUTFILE" | grep -E "(LnkSta|LnkCap|ASPM|^[0-9])" >> "$OUTFILE" 2>&1 || echo "[no NVIDIA PCIe devices found]" >> "$OUTFILE"
echo "" >> "$OUTFILE"

# GPU power state
section "GPU power state"
for dev in /sys/bus/pci/devices/*/vendor; do
    dev_dir="$(dirname "$dev")"
    if [ "$(cat "$dev" 2>/dev/null)" = "0x10de" ] && [ -f "$dev_dir/power_state" ]; then
        bdf="$(basename "$dev_dir")"
        echo "  $bdf: $(cat "$dev_dir/power_state")" >> "$OUTFILE"
    fi
done
echo "" >> "$OUTFILE"

# Xid errors from journal (current boot)
section "Xid errors (current boot)"
journalctl -b -k --no-pager 2>/dev/null | grep -i xid >> "$OUTFILE" 2>&1 || echo "[no Xid errors]" >> "$OUTFILE"
echo "" >> "$OUTFILE"

# NVIDIA systemd services
section "NVIDIA systemd services"
for svc in nvidia-suspend nvidia-resume nvidia-hibernate nvidia-suspend-then-hibernate nvidia-persistenced; do
    enabled="$(systemctl is-enabled "$svc.service" 2>/dev/null || echo 'not found')"
    active="$(systemctl is-active "$svc.service" 2>/dev/null || echo 'inactive')"
    echo "  $svc: enabled=$enabled active=$active" >> "$OUTFILE"
done
echo "" >> "$OUTFILE"

# Runtime PM
section "Runtime PM"
for dev in /sys/bus/pci/devices/*/vendor; do
    dev_dir="$(dirname "$dev")"
    if [ "$(cat "$dev" 2>/dev/null)" = "0x10de" ] && [ -f "$dev_dir/power/runtime_status" ]; then
        bdf="$(basename "$dev_dir")"
        echo "  $bdf runtime_status: $(cat "$dev_dir/power/runtime_status")" >> "$OUTFILE"
        echo "  $bdf runtime_pm: $(cat "$dev_dir/power/control" 2>/dev/null || echo 'N/A')" >> "$OUTFILE"
    fi
done
echo "" >> "$OUTFILE"

echo "Diagnostic saved to: $OUTFILE"
