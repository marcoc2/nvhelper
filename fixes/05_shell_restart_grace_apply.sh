#!/usr/bin/env bash
# Fix 5 — Space out gnome-shell (X11) restarts after a GPU reset on resume
# Confidence: LOW as a fix, useful as a safety net. The session loss itself is
#             mutter bug LP #2040453, fixed by updating mutter (see README).
# Requires: no sudo, no reboot. Run as the desktop user.
#
# Failure chain (Xorg running on the NVIDIA GPU, external HDMI monitor
# attached across an s2idle suspend):
#   1. After resume Xorg logs "NVIDIA: Wait for channel idle timed out" and GL
#      clients (Chrome, Teams, gnome-shell) get GL_GUILTY_CONTEXT_RESET_KHR.
#   2. mutter sees the context reset and re-execs gnome-shell.
#   3. On mutter older than 46.2-1ubuntu0.24.04.5 the new instance aborts with
#      "Another compositing manager is already running" whenever windows are
#      open (LP #2040453), and so does every restart that follows.
#   4. org.gnome.Shell@x11.service retries with RestartSec=0 and each failed
#      start fires OnFailure=gnome-session-failed.target, whose only way out
#      is Log Out.
#
# With mutter updated, step 3 succeeds and the open windows survive. The
# drop-in covers the remaining case of a restart that fails for another
# reason, e.g. while the GPU is still recovering: retries are spaced 5s apart,
# up to 10 (~70s), and RestartMode=direct keeps intermediate failures from
# firing OnFailure=. When every retry fails, the start limit is hit and the
# usual failure screen shows up, as before.
#
# Side effects: an ordinary gnome-shell crash takes ~5s to restart instead of
# restarting immediately; a genuine crash loop (e.g. a broken extension) takes
# ~70s instead of ~4s to reach the failure screen.

set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "Run as the desktop user, not root: this is a systemd --user drop-in." >&2
    exit 1
fi

UNIT="org.gnome.Shell@x11.service"
DROPIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$UNIT.d"
CONF="$DROPIN_DIR/restart-grace.conf"

echo "=== Fix 5: gnome-shell restart grace period ==="

mkdir -p "$DROPIN_DIR"

if [ -f "$CONF" ]; then
    cp "$CONF" "$CONF.bak.$(date +%Y%m%d_%H%M%S)"
    echo "Existing drop-in backed up."
fi

cat > "$CONF" << 'EOF'
# Safety net for gnome-shell restarts after an NVIDIA GPU reset on resume.
# Spacing the retries and skipping OnFailure= on the intermediate ones leaves
# gnome-session-failed.target (forced logout) for the case where the shell
# really cannot come back. Requires mutter >= 46.2-1ubuntu0.24.04.5 to be
# useful at all: older builds cannot restart while windows are open
# (LP #2040453).
[Unit]
StartLimitIntervalSec=120s
StartLimitBurst=10

[Service]
RestartSec=5s
RestartMode=direct
EOF

echo "Created $CONF"
cat "$CONF"

systemctl --user daemon-reload

echo ""
echo "Effective settings:"
systemctl --user show "$UNIT" -p RestartUSec -p RestartMode -p StartLimitBurst -p StartLimitIntervalUSec

echo ""
echo "=== Fix 5 applied (no reboot needed) ==="
echo "mutter version (needs >= 46.2-1ubuntu0.24.04.5):"
dpkg -l libmutter-14-0 | awk '/^ii/{print "  " $3}'
