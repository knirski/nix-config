# ZBook s2idle debugging runbook (deferred)

> Status: deferred 2026-09-11. The instrumented `suspend-debug` Limine entry was
> removed from [`hosts/zbook/boot.nix`](../hosts/zbook/boot.nix) because the
> entry-path hang stopped reproducing. This runbook preserves the rebuild
> recipe, the evidence rules, and the field log so the setup can be restored
> quickly if the failure returns. Until then, treat s2idle on zbook as
> unreliable and prefer shutdown over suspend.

Two s2idle failure modes have been observed on zbook:

1. **Resume path / NVMe wedge** — the machine resumes, then later wedges with
   no kernel log, or wakes with `nvme … VPD access failed` and hangs, sometimes
   dropping btrfs to read-only. See [troubleshooting.md](troubleshooting.md)
   and the zbook known-issues entry in `AGENTS.md`.
2. **Entry-path hang** — first observed 2026-09-11: the machine never resumed;
   the last kernel line was `Filesystems sync: 0.038 seconds`. The RTC showed
   the hang happened before any device-suspend callback, i.e. in the
   `dpm_prepare`/early-entry window, not in the NVMe/GPU/PCI callbacks.

The normal boot keeps general crash capture regardless of this runbook: a 1 MiB
ramoops region (`normalRamoopsParams`), `boot.crashDump` (kdump,
`crashkernel=256M`), and the preserved `/var/lib/systemd/pstore` archive. The
specialisation below only enlarges and instruments that on a dedicated entry.

## 1. Rebuild the instrumented boot

Restore the helper derivations and `debugRamoopsParams` from the
[appendix](#appendix-removed-configuration) into the `let` block of
`hosts/zbook/boot.nix`, then re-add the
`specialisation.suspend-debug.configuration` block. The specialisation:

- patches `PSTORE_CONSOLE`, `PSTORE_FTRACE`, and `PSTORE_PMSG` on and
  `EFI_VARS_PSTORE` off, so ramoops owns the single pstore backend;
- loads `ramoops` from the initrd and reserves 8 MiB at `0x01000000`
  (`debugRamoopsParams`);
- re-declares the merged kernel parameters with `lib.mkForce` (the laptop
  aspect's NIC/dock quirks must be repeated because `mkForce` replaces the
  whole list) and adds the capture parameters:
  - `no_console_suspend`;
  - `crash_kexec_post_notifiers=1` — upstream `panic()` runs `__crash_kexec()`
    before `panic_print` and `kmsg_dump`, so without this neither the ramoops
    console record nor the ftrace dump is written;
  - `initcall_debug`, `pm_debug_messages`, `ignore_loglevel` — print the device
    callback sequence to the live console;
- forces a panic on a silent hang:
  - `kernel.hung_task_panic=1` (uninterruptible D-state block);
  - `kernel.panic_on_rcu_stall=1` (CPU stopped reporting);
  - `kernel.panic_print=16` (`PANIC_PRINT_FTRACE_INFO`) dumps the tracepoint
    ring into the panic log;
- gives the crash/rescue kernel the same ramoops reservation
  (`boot.crashDump.kernelParams`) so it cannot overwrite the evidence;
- installs `suspend-debug-suspend` and arms diagnostics before every suspend
  through the `suspend-debug-arm` unit (`Before=systemd-suspend.service`,
  `WantedBy=sleep.target`);
- runs `suspend-debug-resync-time` after a successful resume, because
  `pm_trace` deliberately perturbs the RTC.

> Design note: the ramoops ftrace zone is fed only by pstore's function recorder
> (`record_ftrace`), which is off by default and useless here anyway — 120 s of
> other-CPU noise overwrites the small ring before `hung_task_panic` fires. The
> low-volume power tracepoints are used instead and survive through the panic
> log.

## 2. Runbook

Deploy, reboot, and select `suspend-debug` in Limine. Verify the entry is live:

```sh
test -e /sys/module/ramoops
mount | grep pstore
cat /proc/sys/kernel/hung_task_panic /proc/sys/kernel/panic_print
cat /proc/sys/kernel/panic_on_rcu_stall
```

One diagnostic cycle (run from a VT, or watch the external monitor — with
`no_console_suspend` and `ignore_loglevel` the last line before a freeze stays
visible):

```sh
sudo suspend-debug-suspend
```

For repeated cycles, keep the diagnostics armed through systemd rather than
writing `/sys/power/state` directly (`rtcwake -m mem` would bypass the arming
unit), and use the RTC alarm to wake:

```sh
sudo rtcwake -m no -s 60 && sudo systemctl suspend
```

Interpret the outcome:

- **Clean cycle** — `PM: suspend exit` and no evidence. The bug is
  intermittent; run more cycles. Empty pstore and no `/proc/vmcore` are the
  expected result of a successful resume, not a setup failure.
- **Panic fired** — the kernel kexecs into the crash/rescue kernel. There:
  ```sh
  ls /proc/vmcore /sys/fs/pstore
  cp /proc/vmcore /persist/vmcore-$(date +%F)
  ```
  NixOS `boot.crashDump` drops into rescue and does not save vmcores itself,
  and `/persist` is the only durable mount. After `systemctl reboot`, the next
  normal boot archives the ramoops records under `/var/lib/systemd/pstore`.
- **Nothing panics within a few minutes** — the freeze is below the kernel
  (firmware/EC/power). Long-press the power button and read the RTC `pm_trace`
  fingerprint on the next boot (see below).

Aim for 20–30 cycles per A/B variant; a handful of clean resumes proves nothing.

## 3. pstore and pm_trace evidence rules

Ramoops captures a panic, not a silent freeze, and it may survive a warm reset
but normally not a long-press power cut. The only witness that survives power
removal is the RTC `pm_trace` fingerprint:

```sh
echo 1 | sudo tee /sys/power/pm_trace
```

A `Magic number` is only trustworthy together with a
`hash matches <file>:<line>` line, or when the early-boot RTC read is a
fingerprint date (`sec=0`, 19xx). A bare device match such as
`memory265: hash matches` without a file line is a bucket collision — the
device hash space is only 1009 buckets and the system has hundreds of `memoryN`
pseudo-devices. `pm_trace` also only covers device suspend/resume callbacks
(not the prepare phase) and disables asynchronous suspend, so if the problem
disappears while it is armed, that itself suggests an ordering race. See the
[kernel suspend debugging guide](https://docs.kernel.org/power/basic-pm-debugging.html).

## 4. Field log

### 2026-09-11 — entry-path hang on the instrumented entry

- The machine ran the `suspend-debug` entry from 2026-09-09 08:45. Of six
  armed suspends, five resumed and the sixth died 2026-09-11 11:01:02,
  immediately after `PM: suspend entry (s2idle)` and `Filesystems sync:
  0.038 seconds`. The journal ends there; a cold reboot followed at 11:06:22.
- The machine was docked: the NVIDIA-driven external display (`DP-6`) and the
  RTL8153 USB Ethernet were connected. This was not the NVMe wedge — no
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
  happened before any device-suspend callback — in the `dpm_prepare`/
  early-entry window. That makes the dock/ACPI/early path the prime suspect for
  this instance.
- After the forced-panic deployment, one armed cycle resumed cleanly and the
  failure could not be reproduced, so the specialisation was removed on
  2026-09-11 and deferred to this runbook.

## 5. Controlled A/B tests

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

## Appendix: removed configuration

These snippets were removed from `hosts/zbook/boot.nix` on 2026-09-11. They are
kept verbatim so the instrumented boot can be rebuilt without archaeology.

The `let`-block additions (helpers plus the larger ramoops region):

```nix
  debugRamoopsParams = [
    # The region is below the crashkernel reservation and large enough to
    # retain useful console/ftrace records across an unclean reboot.
    "memmap=8M$16M"
    "ramoops.mem_address=0x01000000"
    "ramoops.mem_size=0x800000"
    "ramoops.console_size=0x200000"
    "ramoops.ftrace_size=0x200000"
    "ramoops.pmsg_size=0x100000"
    "ramoops.record_size=0x100000"
  ];

  # Checked writeShellApplication (not writeShellScriptBin) with explicit
  # runtimeInputs: the shell-boundaries CI invariant rejects unchecked
  # helpers. Callees resolve through PATH from runtimeInputs, so the
  # store paths stay out of the script bodies.
  suspendDebugArm = pkgs.writeShellApplication {
    name = "suspend-debug-arm";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -euo pipefail

      if [ "''${EUID:-$(id -u)}" -ne 0 ]; then
        printf '%s\n' "Run this command as root from the suspend-debug boot." >&2
        exit 1
      fi

      trace=/sys/kernel/tracing
      pm_trace=/sys/power/pm_trace

      # Keep the trace focused on suspend ordering. These tracepoints are
      # low-volume, so they still hold the pre-hang history when khungtaskd
      # panics 120 s later; pstore's function recorder (record_ftrace) would
      # have been overwritten by other-CPU noise in the meantime. The
      # specialisation's panic_print=16 dumps this ring into the panic log,
      # which kmsg_dump then stores in ramoops.
      printf '%s\n' 0 > "$trace/tracing_on"
      printf '%s\n' nop > "$trace/current_tracer"
      : > "$trace/trace"
      printf '%s\n' power:suspend_resume > "$trace/set_event"
      printf '%s\n' power:device_pm_callback_start >> "$trace/set_event"
      printf '%s\n' power:device_pm_callback_end >> "$trace/set_event"
      printf '%s\n' 1 > "$trace/tracing_on"

      # pm_trace stores the last suspend/resume fingerprint in the RTC, so it
      # remains available after a cold reset. It also disables async suspend,
      # making this a deliberate diagnostic run rather than a normal cycle.
      printf '%s\n' 1 > "$pm_trace"
    '';
  };

  suspendDebugSuspend = pkgs.writeShellApplication {
    name = "suspend-debug-suspend";
    runtimeInputs = [
      suspendDebugArm
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail

      suspend-debug-arm

      exec systemctl suspend
    '';
  };

  suspendDebugResyncTime = pkgs.writeShellApplication {
    name = "suspend-debug-resync-time";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.networkmanager
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail

      # Resume hooks race NetworkManager's link recovery. Wait for a usable
      # connection before restarting timesyncd; it will still retry if the link
      # is not ready within the bounded wait.
      nm-online --quiet --timeout=30 || true
      systemctl restart systemd-timesyncd.service
      sleep 2
    '';
  };
```

The specialisation itself:

```nix
  # Keep the expensive custom kernel and altered suspend behavior out of the
  # daily boot. Select this entry from Limine only for controlled experiments.
  specialisation.suspend-debug.configuration = {
    boot = {
      # These backends are disabled in the stock kernel config. A targeted
      # patch avoids changing the normal kernel while enabling ramoops to
      # retain console, pmsg, and ftrace data for this entry.
      kernelPatches = [
        {
          name = "suspend-debug-pstore";
          patch = null;
          extraConfig = ''
            PSTORE_CONSOLE y
            PSTORE_FTRACE y
            PSTORE_PMSG y
            # efi_pstore otherwise claims the single pstore backend before
            # ramoops is probed, leaving the reserved RAM region unused.
            EFI_VARS_PSTORE n
          '';
        }
      ];
      initrd.kernelModules = [ "ramoops" ];
      kernelParams = lib.mkForce (
        commonKernelParams
        ++ debugRamoopsParams
        ++ [
          # Preserve the laptop aspect's receiver reset and dock wake quirks;
          # mkForce replaces the merged kernel parameter list for this entry.
          "intel_pstate=active"
          "usbcore.quirks=046d:c52b:b,046d:c532:b,0bda:8153:j"
          "nvme_core.default_ps_max_latency_us=0"
          "pcie_aspm=off"
          # Preserve base/NixOS-generated parameters that mkForce would
          # otherwise replace, including crash diagnostics and boot behavior.
          "keyboard.delay=0"
          "keyboard.rate=50"
          "root=fstab"
          "loglevel=4"
          "lsm=landlock,yama,bpf"
          "crashkernel=256M"
          "nmi_watchdog=panic"
          "softlockup_panic=1"
          "no_console_suspend"
          # A silent s2idle-entry hang never reaches kmsg_dump, so ramoops
          # stays empty. Force blocking hangs to panic instead (see the
          # kernel.sysctl block below) and make the panic path write its
          # evidence *before* kdump takes over: kmsg_dump_desc stores the
          # console log in ramoops and panic_print's FTRACE_INFO bit appends
          # the power tracepoints to that same log. Without
          # crash_kexec_post_notifiers=1 the crash kernel runs first and both
          # records are never written.
          "crash_kexec_post_notifiers=1"
          # Print the suspend ordering to the framebuffer console while the
          # machine is still alive; the same messages stay in the kernel log
          # for the ramoops panic dump.
          "initcall_debug"
          "pm_debug_messages"
          "ignore_loglevel"
        ]
      );
      # Turn silent freezes into panics that kdump and ramoops can capture:
      # khungtaskd catches an uninterruptible (D-state) wait, while
      # panic_on_rcu_stall catches a CPU that stopped reporting. The
      # panic_print bit PANIC_PRINT_FTRACE_INFO (0x10) dumps the tracefs ring
      # into the panic log so the power tracepoints survive in ramoops.
      kernel.sysctl = {
        "kernel.hung_task_panic" = 1;
        "kernel.panic_on_rcu_stall" = 1;
        "kernel.panic_print" = 16;
      };
      # The crash/rescue kernel boots from the same kernel and initrd. Give it
      # the same ramoops reservation, otherwise it treats the reserved region
      # as free RAM and overwrites the evidence before it can be read. The
      # first two entries repeat boot.crashDump's defaults.
      crashDump.kernelParams = [
        "1"
        "boot.shell_on_fail"
      ]
      ++ debugRamoopsParams;
    };

    environment.systemPackages = [ suspendDebugSuspend ];

    # DMS/logind idle timeout, lid handling, and an explicit `systemctl
    # suspend` all converge on this unit. Arm diagnostics before the actual
    # transition without making systemd-suspend invoke the suspend helper
    # recursively.
    systemd.services.suspend-debug-arm = {
      description = "Arm suspend diagnostics before every debug suspend";
      before = [ "systemd-suspend.service" ];
      wantedBy = [ "sleep.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${suspendDebugArm}/bin/suspend-debug-arm";
      };
    };

    # pm_trace deliberately perturbs the RTC while diagnosing suspend. Restart
    # timesyncd after the debug sleep operation returns so only this
    # specialisation repairs the wall clock.
    systemd.services.systemd-suspend.serviceConfig.ExecStartPost = [
      "${suspendDebugResyncTime}/bin/suspend-debug-resync-time"
    ];
  };
```

The `lib` function argument is needed again once this block returns, since
`lib.mkForce` is the only use of it in the file.
