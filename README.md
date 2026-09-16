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
