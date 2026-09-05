# ZBook s2idle debugging plan

> Status: debug boot implemented; controlled testing remains outstanding. This
> document does not establish the XPG GAMMIX S70 Blade as the definitive cause.

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
- targeted `PSTORE_CONSOLE=y` and `PSTORE_FTRACE=y` kernel configuration;
- the `no_console_suspend` kernel parameter;
- a larger ramoops area—roughly 8 MiB, with several MiB for ftrace, because
  64 KiB across 20 CPUs is insufficient;
- preservation of `/var/lib/systemd/pstore`;
- a helper that explicitly arms persistent ftrace immediately before a
  controlled suspend.

This requires one local kernel and NVIDIA-module build, but avoids the overhead
and unrelated behavioral changes of a general-purpose debug kernel. Persistent
ftrace is specifically supported by ramoops; see the
[kernel ramoops documentation](https://docs.kernel.org/admin-guide/ramoops.html).

Ramoops is secondary evidence: it may survive a warm reset but normally not a
long-press power cut. The most valuable mechanism for this failure is explicitly
armed `pm_trace`, because its RTC fingerprint survives power removal:

```sh
echo 1 | sudo tee /sys/power/pm_trace
```

The unarmed `Magic number` matches from earlier boots were random collisions
and must remain ignored. `pm_trace` also disables asynchronous suspend, so if
the problem disappears while it is armed, that itself suggests an ordering
race. See the
[kernel suspend debugging guide](https://docs.kernel.org/power/basic-pm-debugging.html).

## 3. Run controlled A/B tests

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

Implement the `suspend-debug` specialisation, correct ramoops loading and
storage, and add a safe trace-arming helper. Then test undocked and iGPU-only
before spending money or changing more NVMe parameters.
