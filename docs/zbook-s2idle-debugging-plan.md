# ZBook s2idle debugging plan

> Status: debug boot implemented; forced-panic capture added 2026-09-11 after
> the first reproduced hang on that entry. Controlled A/B testing remains
> outstanding. This document does not establish the XPG GAMMIX S70 Blade as
> the definitive cause.

The optimal path is to treat s2idle as temporarily unsafe, instrument one
dedicated debug boot, and isolate components one at a time. Replacing the ADATA
immediately would be reasonable for reliability, but the current evidence does
not prove that it caused these particular hangs.

## 1. Protect daily work

- Avoid suspend for now; use shutdown.
- Hibernation is not currently viable: the evaluated configuration has
  `swapDevices = []`, and the live machine has only `/dev/zram0`. Zram cannot
  retain a hibernation image across power loss.
- The installed BIOS is V99 01.12.01, dated 2026-05-05.
- Enabling the existing Intel watchdog will not reliably recover this failure.
  Linux deliberately stops `iTCO_wdt` during s2idle and restarts it during
  resume—the exact transition that hangs here. See the
  [Linux iTCO watchdog source](https://github.com/torvalds/linux/blob/master/drivers/watchdog/iTCO_wdt.c).

## 2. Diagnostic boot specialisation

The `suspend-debug` Limine entry is defined in
[`hosts/zbook/boot.nix`](../hosts/zbook/boot.nix). It keeps the normal entry
unchanged and builds a targeted kernel with `PSTORE_CONSOLE`, `PSTORE_FTRACE`,
and `PSTORE_PMSG`, loads `ramoops` in the initrd, reserves 8 MiB for it, and
preserves `/var/lib/systemd/pstore` across the impermanent-root reboot.

After deploying and rebooting, select `suspend-debug` from Limine. Confirm the
following before testing:

```sh
test -e /sys/module/ramoops
mount | grep pstore
cat /sys/power/pm_trace
```

The controlled suspend helper arms the tracepoints and `pm_trace` immediately
before suspending:

```sh
sudo suspend-debug-suspend
```

After a cold reboot, inspect both the live pstore directory and the archived
copies:

```sh
sudo find /sys/fs/pstore /var/lib/systemd/pstore -maxdepth 1 -type f -print
sudo journalctl -b 0 -k | grep -E 'PM:|pstore|ramoops|suspend|resume'
```

`pm_trace` deliberately disables asynchronous suspend for that run, so this
helper is diagnostic only and should not be used as the normal suspend path.

The implementation deliberately keeps the normal kernel unchanged and uses:

- `ramoops` in `boot.initrd.kernelModules`;
- targeted `PSTORE_CONSOLE=y`, `PSTORE_FTRACE=y`, and `PSTORE_PMSG=y` kernel
  configuration;
- the `no_console_suspend` kernel parameter;
- a larger ramoops area—roughly 8 MiB, with several MiB for ftrace, because
  64 KiB across 20 CPUs is insufficient;
- preservation of `/var/lib/systemd/pstore`;
- a helper that arms the low-volume power tracepoints and `pm_trace`
  immediately before a controlled suspend;
- forced-panic capture (2026-09-11): `hung_task_panic` and
  `panic_on_rcu_stall` turn a silent block into a panic, `panic_print=16`
  appends the tracepoint ring to the panic log, and
  `crash_kexec_post_notifiers=1` makes the panic path write that log to
  ramoops *before* kdump boots the rescue kernel. The crash kernel receives
  the same ramoops reservation so it cannot overwrite the evidence.

This requires one local kernel and NVIDIA-module build, but avoids the overhead
and unrelated behavioral changes of a general-purpose debug kernel. See the
[kernel ramoops documentation](https://docs.kernel.org/admin-guide/ramoops.html)
for the reservation knobs.

> Correction (2026-09-11): the ramoops ftrace zone is only fed by pstore's
> function recorder (`record_ftrace`), which is off by default; enabling it
> does not help because 120 s of other-CPU noise overwrites the small ring
> before `hung_task_panic` fires. The tracepoint ring is used instead and is
> preserved through the panic log.

Ramoops can capture a panic but not a silent freeze, and it may survive a warm
reset but normally not a long-press power cut. The most valuable mechanism for
a hang that never panics is still explicitly armed `pm_trace`, because its RTC
fingerprint survives power removal:

```sh
echo 1 | sudo tee /sys/power/pm_trace
```

A `Magic number` is only trustworthy together with a
`hash matches <file>:<line>` line or an early-boot RTC read that shows a
fingerprint date (`sec=0`); a bare device match such as
`memory265: hash matches` without a file line is a bucket collision. `pm_trace`
also only covers device suspend/resume callbacks—it cannot localise a failure
in the prepare phase—and it disables asynchronous suspend, so if the problem
disappears while it is armed, that itself suggests an ordering race. See the
[kernel suspend debugging guide](https://docs.kernel.org/power/basic-pm-debugging.html).

## 3. Field log

### 2026-09-11 — first reproduced hang on the debug entry

- The machine ran the `suspend-debug` entry from 2026-09-09 08:45. Of six
  armed suspends, five resumed and the sixth died 2026-09-11 11:01:02,
  immediately after `PM: suspend entry (s2idle)` and `Filesystems sync:
  0.038 seconds`. The journal ends there; a cold reboot followed at 11:06:22.
- The machine was docked: the NVIDIA-driven external display (`DP-6`) and the
  RTL8153 USB Ethernet were connected. This was not the NVMe wedge—no
  `VPD access failed`, no btrfs read-only.
- `/sys/fs/pstore` and `/var/lib/systemd/pstore` were empty. Ramoops only
  writes on `kmsg_dump` (panic/oops); a silent freeze writes nothing, and a
  long-press power cut then wipes the reserved DRAM anyway.
- The boot's `PM: Magic number: 10:861:120` / `memory265: hash matches` was a
  false positive and must be ignored:
  - the early RTC read was a normal timestamp (`09:06:20, 2026-09-11`); a real
    fingerprint always has `sec=0` and a 19xx date,
  - a genuine hit also prints `hash matches <file>:<line>` from `.tracedata`;
    there is no such line anywhere in the persisted journal,
  - the device hash has only 1009 buckets and the system has hundreds of
    `memoryN` pseudo-devices, so collisions are expected.
- The real signal was the *absence* of an RTC fingerprint. The kernel writes it
  in `device_suspend()` before the first suspend callback, so this hang
  happened before any device-suspend callback—in the `dpm_prepare`/early-entry
  window, not in the NVMe/GPU/PCI callbacks. That makes the dock/ACPI/early
  path the prime suspect for this instance.
- A/B status: only the docked configuration has failed so far; test undocked
  next.

## 4. Run controlled A/B tests

Use automatic RTC wake and close or save all valuable work first. Change only
one variable per run.

| Test | What it distinguishes |
| ---- | ---------------------- |
| Staged `pm_test` device/platform tests | Driver callback failure versus the actual low-power transition |
| Undocked versus docked | Thunderbolt, RTL8153, USB, or dock interaction |
| iGPU-only/no NVIDIA | NVIDIA/ACPI resume path |
| Linux 6.18 specialisation | Kernel-family regression; Linux 7.1 and 7.2 have both failed |
| `i915.enable_guc=0` | Intel GuC path suggested by repeated post-resume errors |
| Known-good SSD with the ADATA physically removed | Decisive ADATA/PCIe-controller isolation |

Booting from USB while leaving the ADATA installed is not a decisive SSD test:
the controller can still wedge its PCIe link. A physical swap or removal is the
strongest experiment.

Run enough cycles to exceed the observed failure interval. If rapid RTC-driven
cycling reproduces the problem, aim for 20–30 cycles per variant. If it does
not, compare the variants over normal use instead of assuming that a handful
of successful resumes proves the issue fixed.

## Recommended next action

The debug entry now forces a panic on the next silent hang, so the next
reproduction should produce evidence:

1. Select `suspend-debug` in Limine and run `sudo suspend-debug-suspend` from a
   VT or while watching the external monitor. `initcall_debug`,
   `pm_debug_messages`, and `ignore_loglevel` print the last prepare callback
   before a freeze, and the same lines stay in the kernel log.
2. If the entry path blocks, `hung_task_panic` fires after ~120 s; the panic
   dumps the tracepoint ring and console into ramoops, then kdump boots the
   rescue kernel with the same reservation.
3. In the rescue shell, copy `/proc/vmcore` somewhere durable—`/persist` is the
   only persistent mount, and NixOS `boot.crashDump` does not save vmcores
   automatically—then continue with `systemctl reboot`. After the next normal
   boot, `/var/lib/systemd/pstore` holds the archived ramoops records.
4. If nothing panics within a few minutes, the freeze is below the kernel
   (firmware/EC/power); long-press, then read the RTC `pm_trace` fingerprint
   from the next boot.
5. Test undocked and iGPU-only before spending money or changing more NVMe
   parameters.
