#!/usr/bin/env bash
# test_suspend.sh — Automated suspend/resume test with GPU verification
# Usage: sudo ./test_suspend.sh [wake_seconds]
# Default: suspends for 10 seconds via RTC alarm

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIAG_SCRIPT="$SCRIPT_DIR/diagnose.sh"
WAKE_SECONDS="${1:-10}"

echo "=========================================="
echo "  GPU Suspend/Resume Test"
echo "=========================================="
echo "Wake timer: ${WAKE_SECONDS}s"
echo ""

# Pre-suspend diagnostic
echo ">>> Capturing pre-suspend state..."
"$DIAG_SCRIPT" "test_pre_suspend"

# Verify GPU works before suspend
echo ""
echo ">>> Pre-suspend GPU check:"
if nvidia-smi > /dev/null 2>&1; then
    echo "  GPU: OK"
    nvidia-smi --query-gpu=name,temperature.gpu,power.draw --format=csv,noheader 2>/dev/null || true
else
    echo "  GPU: ALREADY FAILED — aborting (GPU must be working before suspend)"
    exit 1
fi

# Set RTC wake alarm
echo ""
echo ">>> Setting RTC wake alarm for ${WAKE_SECONDS}s..."
echo 0 > /sys/class/rtc/rtc0/wakealarm
echo "+${WAKE_SECONDS}" > /sys/class/rtc/rtc0/wakealarm
ALARM="$(cat /sys/class/rtc/rtc0/wakealarm)"
echo "  Alarm set: $ALARM"

# Suspend
echo ""
echo ">>> Suspending system NOW..."
echo "  (will resume in ${WAKE_SECONDS}s)"
systemctl suspend

# Post-resume (execution continues here after wake)
sleep 3  # Give system a moment to fully resume

echo ""
echo ">>> System resumed!"
echo "  Time: $(date)"

# Post-resume diagnostic
echo ""
echo ">>> Capturing post-resume state..."
"$DIAG_SCRIPT" "test_post_resume"

# Check GPU
echo ""
echo ">>> Post-resume GPU check:"
if nvidia-smi > /dev/null 2>&1; then
    echo "  GPU: OK — communication intact!"
    nvidia-smi --query-gpu=name,temperature.gpu,power.draw --format=csv,noheader 2>/dev/null || true
    RESULT="PASS"
else
    echo "  GPU: FAILED — communication lost after resume!"
    RESULT="FAIL"
fi

# Check for Xid errors
echo ""
echo ">>> Xid errors (current boot):"
XID_ERRORS="$(journalctl -b -k --no-pager 2>/dev/null | grep -i xid || true)"
if [ -n "$XID_ERRORS" ]; then
    echo "$XID_ERRORS"
else
    echo "  None found"
fi

echo ""
echo "=========================================="
echo "  RESULT: $RESULT"
echo "=========================================="
echo "Diagnostics saved in: $SCRIPT_DIR/diagnostics/"
