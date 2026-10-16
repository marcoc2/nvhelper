# nvidia-suspend-fix

Fix NVIDIA GPU communication loss after suspend/resume on Linux laptops.

## Problem

After suspend or screen lock, `nvidia-smi` fails and the GPU becomes unresponsive — requiring a full reboot. This is a well-known issue on hybrid GPU laptops (NVIDIA + Intel/AMD iGPU) running recent NVIDIA drivers on Linux.

**Symptom**: `nvidia-smi` returns `"Unable to communicate with NVIDIA driver"` after resume.

**Root cause**: The kernel module parameter `NVreg_PreserveVideoMemoryAllocations` is not set by default. Without it, the NVIDIA systemd suspend/resume services run but do nothing — VRAM is not saved/restored across sleep cycles. The kernel log confirms this with **Xid Error 31** (MMU Fault, PDE access violation) on resume.

## Solution (Fix 1 — works for most people)

```bash
sudo ./fixes/01_preserve_vram_apply.sh
sudo reboot
```

This creates `/etc/modprobe.d/nvidia-power-management.conf` with:

```
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia_drm fbdev=1
```

And enables the NVIDIA systemd suspend/hibernate services.

**Verify after reboot:**

```bash
cat /sys/module/nvidia/parameters/PreserveVideoMemoryAllocations  # should print 1
```

### Revert

```bash
sudo ./fixes/01_preserve_vram_revert.sh
sudo reboot
```

## Additional Fixes

If Fix 1 alone doesn't solve it, apply incrementally:

| # | Script | What it does | Confidence | Reboot? |
|---|--------|-------------|------------|---------|
| 1 | `fixes/01_preserve_vram_*` | Enable VRAM preservation + fbdev | **High** | Yes |
| 2 | `fixes/02_persistence_mode_*` | Enable nvidia-persistenced persistence mode | Medium | No |
| 3 | `fixes/03_pcie_aspm_*` | Disable PCIe ASPM via GRUB | Low | Yes |
| 4 | `fixes/04_blacklist_ucsi_*` | Blacklist `ucsi_acpi` (see below) | Medium | Yes |
| 5 | `fixes/05_shell_restart_grace_*` | Space out gnome-shell restarts — safety net only, the real fix is a mutter update (see below) | Low | No |

Each fix has an `_apply.sh` and `_revert.sh` script.

## Related issue — session crash on external monitor connect

Separate from the suspend/resume VRAM loss above: connecting an external
monitor through the USB-C/Thunderbolt dock can kill the desktop session
(GNOME reports `gnome-session-failed.target` and forces a relogin). This is
not an Xid error and not a GPU crash — `nvidia-smi` stays healthy through it.

Root cause found in `journalctl -b -k`: the kernel's UCSI connector-change
handler hogs the CPU while negotiating the dock connection —
`workqueue: ucsi_handle_connector_change [typec_ucsi] hogged CPU for
>10000us`, preceded by `ucsi_acpi USBC000:00: UCSI_GET_PDOS failed (-5)`.
Long enough of that and `gnome-shell` stops responding, so `gnome-session`
declares the session failed and tears it down. This is a widely reported
Linux kernel/firmware quirk on Intel USB-C controllers (Framework, Dell XPS,
ThinkPad, others), independent of the NVIDIA driver.

Session type (X11 vs Wayland) is not a reliable fix here — the CPU-hogging
happens in the kernel before either display server gets a say, and NVIDIA's
own hybrid + Wayland + external-monitor-hotplug combination has open bugs of
its own (displays going permanently blank on hotplug), so switching to
Wayland was ruled out for this laptop.

Workaround: `fixes/04_blacklist_ucsi_*` blocks the `ucsi_acpi` module. Needs
a reboot, and needs verifying afterward that dock charging and USB-C role
negotiation still work, since `ucsi_acpi` also carries USB Power Delivery
reporting — see the script's own comments before running it.

## Related issue — session crash on resume with an external monitor

Also separate from the VRAM loss: with Fix 1 in place `nvidia-smi` survives
resume, yet the desktop session can still die a few seconds after waking up.
It only shows up when an external monitor is attached to the NVIDIA HDMI
port across the suspend; resumes with just the laptop panel came back clean.

Sequence in `journalctl -b`:

1. Xorg: `(WW) NVIDIA: Wait for channel idle timed out.` (two or three
   times, 5–10s apart), and GL clients log `GL_GUILTY_CONTEXT_RESET_KHR`.
2. mutter sees the reset and re-execs gnome-shell (`Running GNOME Shell` with
   the same PID).
3. The new instance aborts with `Another compositing manager is already
   running on screen 0`. Despite the message, no other compositor exists:
   the X error is BadAccess on Composite `RedirectSubwindows(root, Manual)`,
   and mutter causes it itself. While adopting the windows that are already
   open — left as unframed children of the root once the old shell's frames
   died — it redirects each of them with `RedirectWindow(Manual)` before
   redirecting the root's children, and the server refuses the second manual
   redirection of those windows. Every start with windows open fails the
   same way, so waiting or retrying never helps.
4. `org.gnome.Shell@x11.service` keeps retrying, every failed start fires
   `OnFailure=gnome-session-failed.target`, and the "Oh no! Something has
   gone wrong" screen only offers Log Out.

This is mutter bug [LP #2040453](https://bugs.launchpad.net/bugs/2040453)
("restarting gnome-shell on X11 crashes the session unless every application
is closed first"), fixed in Ubuntu's `mutter 46.2-1ubuntu0.24.04.5`. The
affected machine was still on `46.2-1ubuntu0.24.04.1`: unattended-upgrades
only installs security updates, and mutter ships through `noble-updates`.

No Xid is logged and the GPU stays usable, so the NVIDIA part is a stall in
the X driver's channel recovery, not a lost GPU. That stall still happens
after the update; the difference is that the shell now restarts with the
windows in place instead of taking the session down.

### Fix: update mutter and gnome-shell

```bash
dpkg -l libmutter-14-0 | awk '/^ii/{print $3}'   # needs >= 46.2-1ubuntu0.24.04.5
sudo apt install -o APT::Get::Always-Include-Phased-Updates=true \
    libmutter-14-0 gir1.2-mutter-14 mutter-common mutter-common-bin \
    gnome-shell gnome-shell-common
```

The phased-updates option only matters while the newest mutter build is still
being phased in; without it `apt` keeps the packages back. Log out and back in
afterwards, since the running shell keeps the old library loaded.

To verify, follow the test plan from the bug report: open a few windows, press
Alt+F2, type `r`, press Enter. The shell reloads and the windows stay open.

### Safety net: Fix 5

`fixes/05_shell_restart_grace_*` installs a systemd `--user` drop-in for
`org.gnome.Shell@x11.service` that spaces retries 5s apart (up to 10 within
2 minutes) with `RestartMode=direct`, so intermediate failures do not bring
up the failure screen. It fixes nothing on its own — on the old mutter all ten
retries failed — but it gives the shell more chances if a restart happens
while the GPU is still recovering. Run it as the desktop user, not with sudo;
it takes effect immediately.

### Side effect: screens blank after a few seconds idle

Even when the shell restart succeeds, `gsd-power` can lose its connection to
mutter's idle monitor in the process. The journal shows it in the same second
as the shell restart:

```
gsd-power: Failed to acquire idle monitor proxy: GDBus.Error:org.freedesktop.DBus.Error.NoReply: Message recipient disconnected from message bus without replying
```

From then on both screens go black together after a few seconds without
keyboard or mouse input and come back as soon as there is input, regardless of
`org.gnome.desktop.session idle-delay` (it was `0`, i.e. never). It is a DPMS
power-off, not a GPU or cable problem: the X framebuffer keeps its contents
while the outputs are off, and `dbus-monitor` shows `gsd-power` setting
`PowerSaveMode` on `org.gnome.Mutter.DisplayConfig` to `3` (off) and back to
`0` on every blackout.

Check:

```bash
journalctl --user -b -u org.gnome.SettingsDaemon.Power.service | grep "idle monitor proxy"
dbus-monitor --session "type='method_call',member='Set',path='/org/gnome/Mutter/DisplayConfig'"
```

Fix, without logging out — restart `gsd-power`:

```bash
systemctl --user kill org.gnome.SettingsDaemon.Power.service
systemctl --user restart org.gnome.SettingsDaemon.Power.target
systemctl --user show org.gnome.SettingsDaemon.Power.service -p MainPID -p ActiveEnterTimestamp
```

The service refuses a plain `systemctl --user restart` (`RefuseManualStart`
and `RefuseManualStop`), and after `kill` it stays down instead of restarting
on its own; restarting its target pulls it back in as a dependency. Neither
step touches the rest of the session. The last command should show a new PID
and a start time of a few seconds ago.


## Diagnostic Tools

### diagnose.sh — GPU state snapshot

Captures a full snapshot: nvidia-smi output, loaded modules, kernel parameters, PCIe link status, Xid errors, power state, and systemd service status.

```bash
sudo ./diagnose.sh baseline        # before any changes
sudo ./diagnose.sh post_fix1       # after applying fix 1
sudo ./diagnose.sh post_resume     # after a suspend/resume cycle
```

Output is saved to `diagnostics/<label>_<timestamp>.log`.

### test_suspend.sh — automated suspend/resume test

Captures pre-suspend state, suspends via RTC alarm, then checks GPU communication on resume.

```bash
sudo ./test_suspend.sh        # suspend for 10s (default)
sudo ./test_suspend.sh 30     # suspend for 30s
```

### watchdog.sh — continuous GPU monitor

Polls `nvidia-smi` every 30s. On failure, automatically captures diagnostics.

```bash
sudo ./watchdog.sh
```

Or install as a systemd service:

```bash
sudo cp gpu-watchdog.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now gpu-watchdog.service
```

Logs are saved to `watchdog_logs/`.

## Tested On

- Dell Inspiron 16 — NVIDIA GeForce RTX 4060 Max-Q + Intel Arc (hybrid)
- Ubuntu 24.04.1 LTS, kernel 6.14.0-37-generic
- NVIDIA driver 570.211.01, CUDA 12.8

## References

- [NVIDIA Driver Documentation — Power Management](https://download.nvidia.com/XFree86/Linux-x86_64/570.211.01/README/powermanagement.html)
- [Arch Wiki — NVIDIA/Tips and tricks #Preserve video memory after suspend](https://wiki.archlinux.org/title/NVIDIA/Tips_and_tricks#Preserve_video_memory_after_suspend)

## License

MIT
