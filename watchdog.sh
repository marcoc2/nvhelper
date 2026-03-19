#!/usr/bin/env bash
# watchdog.sh — Continuous NVIDIA GPU communication monitor
# Tests nvidia-smi every 30s. On failure, captures diagnostics automatically.
# Usage: sudo ./watchdog.sh
# Or as a systemd service: systemctl start gpu-watchdog

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$SCRIPT_DIR/watchdog_logs"
DIAG_SCRIPT="$SCRIPT_DIR/diagnose.sh"
INTERVAL="${GPU_WATCHDOG_INTERVAL:-30}"

mkdir -p "$LOG_DIR"

LOGFILE="$LOG_DIR/watchdog_$(date +%Y%m%d_%H%M%S).log"
FAIL_COUNT=0
CHECK_COUNT=0

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

log "GPU watchdog started (interval=${INTERVAL}s)"
log "PID: $$"

cleanup() {
    log "Watchdog stopped (checks=$CHECK_COUNT, failures=$FAIL_COUNT)"
    exit 0
}
trap cleanup SIGTERM SIGINT

while true; do
    CHECK_COUNT=$((CHECK_COUNT + 1))

    if nvidia-smi > /dev/null 2>&1; then
        # Log every 10th successful check to avoid bloat
        if (( CHECK_COUNT % 10 == 0 )); then
            log "OK (check #$CHECK_COUNT)"
        fi
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        log "FAILURE #$FAIL_COUNT — nvidia-smi failed (check #$CHECK_COUNT)"

        # Capture diagnostic dump
        if [ -x "$DIAG_SCRIPT" ]; then
            log "Running diagnostic capture..."
            "$DIAG_SCRIPT" "watchdog_fail_${FAIL_COUNT}" 2>&1 | tee -a "$LOGFILE" || true
        fi

        # Save dmesg tail
        DMESG_FILE="$LOG_DIR/dmesg_fail_${FAIL_COUNT}_$(date +%Y%m%d_%H%M%S).log"
        dmesg --time-format iso | tail -100 > "$DMESG_FILE" 2>/dev/null || true
        log "dmesg saved to: $DMESG_FILE"

        # Save journal nvidia entries
        JOURNAL_FILE="$LOG_DIR/journal_fail_${FAIL_COUNT}_$(date +%Y%m%d_%H%M%S).log"
        journalctl -b --no-pager -k 2>/dev/null | grep -iE "(nvidia|nvrm|xid|gpu)" > "$JOURNAL_FILE" 2>/dev/null || true
        log "journal saved to: $JOURNAL_FILE"
    fi

    sleep "$INTERVAL"
done
