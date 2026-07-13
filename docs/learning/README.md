# Learning Path — Soyo DNS/DHCP Appliance

A guided entry point for this repository's code and the Nix/NixOS concepts it uses. Read in order — each section builds on the last and maps to a milestone in the [Soyo design doc](../superpowers/specs/soyo-dns-dhcp-appliance.md).

## Reading order & roadmap

| # | Document | Milestone | What you'll learn |
| --- | ---------- | ----------- | ------------------- |
| 1 | This README | — | Glossary, repo layout, dendritic wiring |
| 2 | [Nix language basics](https://nix.dev/tutorials/nix-language) (nix.dev) | — | The Nix expression language — read before the flake |
| 3 | [Flakes](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake) (Nix manual) | — | What a flake is, inputs/outputs |
| 4 | [flake-parts](https://flake.parts) | M1 | Modular flake outputs, perSystem |
| 5 | [Design doc](../superpowers/specs/soyo-dns-dhcp-appliance.md) | All | Every architectural decision and why |
| 6 | `flake.nix` | M1 | The entry point — thin, delegates to flake-parts; `vic/import-tree` auto-imports every module under `modules/` |
| 7 | `modules/parts/soyo.nix`, `modules/parts/aspect-options.nix` | M1 | How a host is assembled by toggling aspects; `aspect-options.nix` defines the `aspects.nixos` and `aspects.homeManager` option namespaces that make the aspect system work |
| 8 | `modules/nixos/base.nix` → `ssh.nix` → `server.nix` → `tailscale.nix` → `users.nix`, [Host role models](host-role-models.md) | M1 | The role-neutral base, explicit aspects, typed role registries and boundary checks. `ssh.nix` was extracted from `server.nix` and `workstation.nix` — key-only auth, configurable ports, agent forwarding |
| 9 | `modules/nixos/persistence.nix`, `hosts/soyo/persistence.nix` | M1 | Impermanence via blank-snapshot rollback + the concrete persisted-path inventory, including why boot signing state like `/var/lib/sbctl` belongs in it |
| 10 | `modules/nixos/blocky.nix`, `hosts/soyo/dns.nix` | M1 | DNS with blocking (Blocky) |
| 11 | `modules/nixos/dhcp.nix`, `hosts/soyo/dhcp.nix` | M1 | DHCP + reverse DNS (dnsmasq) |
| 12 | `modules/nixos/remote-unlock.nix`, `hosts/soyo/initrd-unlock.nix` | M1 | TPM auto-unlock + break-glass paths |
| 13 | [agenix/agenix-rekey](https://github.com/ryantm/agenix), `docs/secrets.md` | M1 | Encrypted secrets, rekeyFile flow |
| 14 | `modules/nixos/maintenance.nix` | M2 | Scheduled upkeep: gc, scrub, SMART, ntfy alerts |
| 15 | `modules/nixos/backup.nix`, `hosts/soyo/backup.nix` | M2 | restic to Synology, btrbk local snapshots |
| 16 | `modules/nixos/observability.nix`, `lib/observability/`, `hosts/soyo/observability.nix`, [`docs/topology/`](../topology/) | M2 | Exporters, on-box Grafana, Loki logs, Tempo traces, Alloy journal shipping. Reusable helpers extracted to `lib/observability/` (outside `import-tree`'s scope — see comment in the module). LAN observability adds passive inventory collector (`modules/nixos/observability/lan_inventory.py`), blackbox probes (ICMP + HTTP), an `LAN Overview` dashboard, and topology diagrams under `docs/topology/`. Host-local network metadata lives in `hosts/soyo/network.nix` (separated from the DHCP schema to keep the critical path boring). |
| 17 | `hosts/soyo/boot.nix` | M3 | Limine Secure Boot, TPM PCR binding, and Limine's `sbctl` signing model |
| 18 | `modules/parts/perSystem.nix`, [Verification layers](verification-layers.md) | All | Dev shell, formatter, pre-commit hooks, pure checks, strict-KVM VM tests and CI/Cachix boundaries |
| 19 | `modules/nixos/tailscale.nix` | M2 | Tailscale mesh VPN, remote admin without open ports |
| 20 | [CI design doc](../superpowers/specs/2026-07-05-ci-pipeline-design.md), [CI plan](../archive/2026-07-05-ci-pipeline-plan.md), `.github/workflows/ci.yml`, `modules/nixos/observability.nix` (Grafana alerts) | M2 | CI pipeline (lint: deadnix + statix + typos + gitleaks + actionlint + shellcheck + markdownlint + ruff → eval: `nix flake check` → build + closure diff → topology artifact), Grafana alerting (disk, backup, service health via ntfy), backup Prometheus metric |
| 21 | `modules/nixos/laptop.nix`, `modules/nixos/workstation.nix` | M4 (shipped) | Laptop power management (power-profiles-daemon, thermald, lid switch, USB/Thunderbolt wake fixes); workstation is now a minimal role marker (docker moved to host data, SSH agent extracted to `ssh.nix`) |
| 22 | `modules/nixos/desktop.nix`, `modules/nixos/sway.nix`, `modules/home/desktop.nix`, `modules/home/sway.nix`, `modules/home/ssh.nix` | M4 (shipped) | Role-neutral desktop services plus the Sway session, DMS greetd greeter, shell, and user configuration. `modules/home/ssh.nix` provides per-user SSH client config (GitHub key, host entries) |
| 23 | `modules/nixos/nvidia.nix` | M4 (shipped) | NVIDIA proprietary driver (RTX 4000 Ada), prime sync, offload modes |
| 24 | `modules/nixos/gaming.nix` | M4 (shipped) | Steam, gamemode, MangoHud, game-specific tweaks |
| 25 | `modules/parts/zbook.nix`, `hosts/zbook/` | M4 (shipped) | zbook host assembler — toggles 12 aspects (base, ssh, tailscale, desktop, sway, nvidia, laptop, gaming, workstation, users, persistence, maintenance, backup) onto the same base modules used by Soyo |
| 26 | Nvidia bug (this section) | M4 | The read-only `hardware.nvidia.enabled` trap |
| 27 | s2idle over deep S3 (this section) | M4 | HP firmware wake routing: S3 enters but never resumes; s2idle is the native suspend mode |
| 28 | `modules/nixos/laptop.nix` — `usbcore.quirks` | M4 (shipped) | Kernel-level USB autosuspend disable for Logitech receivers — immutable, immune to powertop |
| 29 | Historical COSMIC workaround (this section) | M4 (shipped) | Why the compositor-specific SIGSTOP/SIGCONT workaround was removed when zbook migrated away from COSMIC |
| 30 | deploy-rs | M4 (shipped) | `deploy .#hostname` for remote deploys with magic rollback; `deployChecks` wired into `nix flake check`; deploy script auto-detects local vs remote |
| 31 | SSH key rotation | M4 (shipped) | When the master SSH key becomes incompatible (old OpenSSH format + OpenSSL 3.6.2), generate a fresh one, re-encrypt all `.age` files, update `krzysiek-authorized-key.pub`, and rekey for all hosts |
| 32 | Secrets recovery from git history | M4 (shipped) | If master `.age` files get corrupted (empty decryption), recover plaintext from pre-corruption rekeyed files using the host's own SSH key via `rage -d -i /persist/etc/ssh/ssh_host_ed25519_key`, then re-encrypt with the new master key |
| 33 | agenix native SSH recipients | M4 (shipped) | Master `.age` files must use `rage -e -R <SSH pubkey>` (native SSH recipient), *not* `rage -e -r age1...` (X25519 age recipient) — agenix-rekey with `masterIdentities` pointing to an SSH key only works with `-> ssh-ed25519` recipients |
| 34 | Per-host Tailscale auth keys | M4 (shipped) | Shared auth keys don't work well once you have multiple hosts. Split into `tailscale-auth-key-soyo.age` and `tailscale-auth-key-zbook.age`, declared in the host assembler rather than the shared `users.nix` |
| 35 | sbctl persistence on impermanent root | M3/M4 | On an erase-your-darlings root, `/var/lib/sbctl` must be persisted (preservation module, mode 0700) or Secure Boot keys disappear on reboot. If lost, return to BIOS Setup Mode, run `sbctl create-keys && sbctl enroll-keys -m`, deploy once, re-enable Secure Boot |
| 36 | Limine config checksum mismatch panic recovery | M3 | If `panicOnChecksumMismatch` is `true` and the config file hash doesn't match, Limine panics before the kernel loads. Recovery: boot from live USB, mount ESP, edit `/limine/limine.conf` — set `panic_on_checksum_mismatch: false` or delete `config_file_checksum:` line, then reboot and redeploy |
| 37 | deploy-rs magic rollback and DNS | M4 | deploy-rs's confirmation hook connects back to the target host by hostname. If DNS doesn't resolve (e.g. zbook can't resolve `soyo` because it's on a different network), the confirmation fails and the deployment gets rolled back. Workaround: ensure DNS works or use `nixos-rebuild --target-host <IP> --sudo` as fallback |

## What is this repo?

A NixOS flake that configures a small Intel N150 box ("Soyo") as a LAN DNS and DHCP appliance and an HP ZBook Studio G10 ("zbook") as a desktop/gaming workstation. The repository doubles as a deliberate way to learn modern Nix — see [Learning Goals](../superpowers/specs/soyo-dns-dhcp-appliance.md#learning-goals).

## Glossary

**Flake** — A self-contained Nix expression with locked inputs (`flake.lock`). Root is `flake.nix`.

**flake-parts** — A framework that splits a flake into composable modules. Each module can contribute to outputs (packages, checks, dev shells, NixOS configs).

**Dendritic pattern** — `flake.nix` calls `inputs.import-tree ./modules`, which
auto-imports eligible `.nix` files as flake-parts modules. `_`-prefixed paths
such as `modules/_pkgs/` are skipped. Aspect files contribute to a shared
namespace such as `aspects.nixos.<aspect>`; a host assembler still has to opt
into each aspect, so discovery does not enable features by itself.

**Aspect module** — One file under `modules/nixos/` or `modules/home/` that exposes a toggleable feature. Convention: `{ aspects.nixos.<name> = { ... }; }` with an
`options.lanAppliance.*` namespace for host data.

**Host assembler** — A flake-parts module (e.g. `modules/parts/soyo.nix`) that builds a `nixosConfiguration` by listing which aspects to toggle and importing host-specific data files.

**Host data file** — A plain NixOS module under `hosts/soyo/` that provides host-specific values (disko layout, networking, reservations, backup targets). Not an aspect — just data imported by the assembler.

**Impermanence (erase-your-darlings)** — The root filesystem is wiped to a blank Btrfs snapshot on every boot. Only explicitly declared paths under `/persist` survive. Forces an inventory of what state actually matters.

**preservation** — The NixOS module that manages the persisted-path inventory and bind-mounts `/persist` contents back into runtime paths.

**DynamicUser / StateDirectory** — A systemd pattern where a service gets a transient UID and a managed state directory. On NixOS this often lands under `/var/lib/private/<name>`, so impermanence requires checking those private paths explicitly, not just the obvious `/var/lib/<name>`.

**TPM2 auto-unlock** — The LUKS2 encryption key is enrolled against the TPM's Platform Configuration Registers (PCRs). If the measured boot hasn't changed, the TPM releases the key without a passphrase — so power loss recovers unattended.

**PCR (Platform Configuration Register)** — A TPM register that hashes boot components. If firmware, bootloader, or Secure Boot state changes, PCR values change and the TPM won't release the key — the passphrase fallback is used instead.

**rekeyFile** — agenix-rekey's flow: secrets are master-encrypted with the operator's key, then rekeyed per-host at deploy time. Each host gets its own copy encrypted with its SSH host key.

**sbctl file database** — sbctl's internal list of EFI binaries it tracks as signed. In this repo, the NixOS Limine module uses `sbctl` to sign `BOOTX64.EFI` directly during activation, so Secure Boot can be working even if `sbctl status` still reports no installed files.

**Tailscale** — A WireGuard-based mesh VPN that assigns each device a stable IP
in your tailnet. No open firewall ports, no DynDNS. Soyo joins automatically
using an encrypted auth key, so you can SSH in from anywhere.

**home.arpa** — The IANA-reserved special-use domain for home networks (RFC 8375). Used as the local search domain instead of `.local` (reserved for mDNS) or a made-up TLD.

## How the dendritic pattern works

Given `hosts/soyo`, what's actually turned on? The answer is in `modules/parts/soyo.nix`:

```nix
modules = (with config.aspects.nixos; [
  base server users persistence remote-unlock blocky dhcp
  maintenance backup observability
]) ++ [ ... host data files ... ]
```

Each name in that list is an aspect contributed by a file under
`modules/nixos/`. Because `vic/import-tree` discovers eligible `.nix` files
under `modules/`, adding an aspect means creating its file, exposing
`aspects.nixos.<name>` (or `aspects.homeManager.<name>`), and toggling it in the
appropriate host assembler. Plain reusable Nix helpers belong under `lib/`,
outside import-tree's module tree.

## M4 learnings: NVIDIA and laptop suspend fixes

Two gotchas came up during zbook setup that are worth understanding because
they show how NixOS's option system interacts with real hardware quirks.

### The `hardware.nvidia.enabled` trap

The `nvidia.nix` module sets every NVIDIA sub-option you'd expect:
`modesetting.enable`, `powerManagement.enable`, `prime.offload.enable`, the
driver package — but it never added `"nvidia"` to `services.xserver.videoDrivers`.

Here's why that matters: `hardware.nvidia.enabled` is a **read-only** option
(`readOnly = true`). Its default value is computed from whether `"nvidia"` is
in `services.xserver.videoDrivers`:

```nix
nvidiaEnabled = lib.elem "nvidia" config.services.xserver.videoDrivers;
enabled = lib.mkOption {
  readOnly = true;
  type = lib.types.bool;
  default = nvidiaEnabled || cfg.datacenter.enable;
};
```

If `videoDrivers` is `["modesetting" "fbdev"]` (the default), then
`hardware.nvidia.enabled` stays `false`, the NVIDIA module in nixpkgs
skips its `mkIf cfg.enabled` block, and **nouveau loads instead**. No GPU
acceleration, terrible desktop performance.

**The fix** — add `services.xserver.videoDrivers = [ "nvidia" ];` in the
aspect module's config block. This makes `hardware.nvidia.enabled = true`,
which triggers all the nvidia-persistenced service, kernel module loading,
nouveau blacklist, and proper GPU initialization:

```nix
config = lib.mkIf cfg.enable {
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    ...
  };
};
```

After this change, a **reboot** is required (nouveau already has the GPU
claimed; the NVIDIA module can't hot-swap).

### s2idle (S0ix) over deep S3: the HP firmware wake routing problem

The first attempt forced deep S3 sleep on zbook with `mem_sleep_default=deep`
in `hosts/zbook/boot.nix`. The system *entered* S3 fine — `PM: suspend entry
(deep)` in the logs — but **never woke up**. Zero `PM: Low-level resume`
events, zero `suspend exit`. The power button, lid, and keyboard all had no
effect; only holding the power button for a cold reboot worked.

The root cause: this HP ZBook Studio G10 firmware is designed for **Windows
Modern Standby (S0ix)**. The PCH (Platform Controller Hub) wake routing is
configured for S0ix-native interrupt paths, not S3 GPIO/SMI wake paths. The
firmware advertises S3 in ACPI FADT (so Linux doesn't refuse to boot), but
the wake event controller never re-sequences the power rails after S3 entry.

This is confirmed by [HP Support Community
threads](https://h30434.www3.hp.com/t5/Business-Notebooks/HP-Zbook-G10-sleep-and-modern-standby-issues/td-p/8888712)
and the [Arch Wiki](https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate):
> Manufacturers have stopped fixing bugs with the ACPI S3 state since systems
> shipping with Windows are encouraged to use "Modern standby" by default; if
> they have voluntarily not advertised it, it is probably broken in some way.

The current fix is to use s2idle, the firmware-native suspend mode. A former
COSMIC-specific resume hook also delayed display re-probing for the USB-C dock,
but it was removed with COSMIC; the current Sway configuration does not claim
to provide that hook.

### Udev rules for targeted dock Ethernet wake suppression

On s2idle, the dock's Realtek RTL8153 Ethernet adapter generates link-state
changes that immediately wake the system after suspend entry. The fix is a
single udev rule targeting the USB vendor/product ID:

```nix
services.udev.extraRules = lib.mkAfter ''
  ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="8153", ATTR{power/wakeup}="disabled"
'';
```

Earlier iterations used blanket `xhci_hcd` and `thunderbolt` driver-class
rules, but those were too broad — they disabled wake for all USB devices
(including the Logitech keyboard receiver), making the machine unreachable
after lid-close suspend.

### `usbcore.quirks`: kernel-level USB autosuspend disable for Logitech receivers

The Logitech Unifying and Bolt receivers (mouse + keyboard) would disconnect
and reconnect every few seconds, making them unusable. The first attempt used
udev rules to set `power/control=on` on the USB device — but `powertop
--auto-tune` runs later and overrides this back to `auto`, re-enabling
autosuspend.

The proper fix is a kernel parameter:

```nix
boot.kernelParams = [ "usbcore.quirks=046d:c52b:b,046d:c532:b" ];
```

The `usbcore.quirks=` parameter is parsed by the USB core at boot, *before*
any userspace (udev, powertop) runs. The `b` flag calls
`usb_disable_autosuspend()` during the device probe sequence — the USB core
will never autosuspend those devices, regardless of what powertop or udev
does later.

This is the cleanest approach because:
- **Immutable** — once set, no userspace can re-enable autosuspend for these
  devices (powertop writes `power/control` but the USB core ignores it).
- **Zero runtime cost** — no services, no polling, no race conditions.
- **Kernel-native** — the quirk mechanism is part of the USB core, not a
  workaround.

The udev rules were removed once the quirk was confirmed working — they only
raced with powertop and provided no value with the quirk in place.

### Historical: SIGSTOP/SIGCONT for cosmic-comp on suspend/resume

With dual Intel+NVIDIA PRIME offload, `cosmic-comp` (the COSMIC compositor)
would lose DRM master after suspend. The log told the story:

```text
nvidia-suspend.service starts → nvidia-sleep.sh does chvt 63
cosmic-comp gets udev event → tries to clear state on card1
→ hits DRM EACCES (Permission denied) because VT switched away
```

The `nvidia-suspend.service` needs to save GPU state, which requires taking
over the DRM device. But cosmic-comp still holds DRM master. The VT switch
(`chvt 63`) inside `nvidia-sleep.sh suspend` triggers a udev event that
cosmic-comp tries to handle — but it's already lost DRM master permissions.

At the time, the fix was the standard Wayland compositor suspend pattern:
**SIGSTOP before the VT switch, SIGCONT after the GPU resumes**.

The SIGSTOP had to be `ExecStartPre` on `nvidia-suspend.service` — not
`powerManagement.powerDownCommands` (which goes into `sleep-actions.service
ExecStart`). They run in parallel and `nvidia-sleep.sh`'s `chvt 63` races
ahead of SIGSTOP. With `ExecStartPre`, the freeze is guaranteed to fire
before `ExecStart`.

The SIGCONT + display re-probe went in `nvidia-resume.service ExecStartPost`.
The script waited 2s for the USB-C dock to re-enumerate
(critical on s2idle), then polls NVIDIA external connectors for up to 10s,
then triggers `udevadm change` on each to simulate a hotplug uevent.

The full execution sequence during suspend/resume:

| Step | What happens | Who |
|------|-------------|-----|
| 1 | SIGSTOP cosmic-comp | `nvidia-suspend.service ExecStartPre` |
| 2 | `nvidia-sleep.sh suspend` (chvt 63, save GPU BARs/VRAM) | `nvidia-suspend.service ExecStart` |
| 3 | System suspends (s2idle) | Kernel |
| 4 | System resumes | Kernel |
| 5 | `nvidia-sleep.sh resume` (restore GPU state) | `nvidia-resume.service ExecStart` |
| 6 | Sleep 2s for dock re-enumeration | `nvidia-resume.service ExecStartPost` |
| 7 | SIGCONT cosmic-comp | `nvidia-resume.service ExecStartPost` |
| 8 | Poll NVIDIA connectors for up to 10s, then udevadm trigger | `nvidia-resume.service ExecStartPost` |

This sequence is retained here as a debugging lesson, not as a description of
the current system. Commit `7363e60` deliberately deleted `cosmic.nix` when
zbook migrated from COSMIC to Hyprland; subsequent changes migrated the host to
DMS and Sway. The active NVIDIA module keeps the GSP firmware workaround and
disables systemd's user-session freeze, but it does not install compositor
SIGSTOP/SIGCONT or dock re-probe hooks.

## Canonical sources

| Topic | Link |
| ----- | ---- |
| Nix language | [nix.dev tutorial](https://nix.dev/tutorials/nix-language) |
| Flakes | [Nix manual](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake) |
| flake-parts | [flake.parts](https://flake.parts) |
| NixOS options | [search.nixos.org](https://search.nixos.org/options) |
| NixOS manual | [nixos.org](https://nixos.org/manual/nixos/stable/) |
| Nixpkgs manual | [nixos.org](https://nixos.org/manual/nixpkgs/stable/) |
| Home Manager | [home-manager](https://nix-community.github.io/home-manager/) |
| agenix | [github.com/ryantm/agenix](https://github.com/ryantm/agenix) |
| Blocky | [0xerr0r.github.io/blocky](https://0xerr0r.github.io/blocky/) |
| dnsmasq | [thekelleys.org.uk/dnsmasq](https://thekelleys.org.uk/dnsmasq/doc.html) |
| restic | [restic.readthedocs.io](https://restic.readthedocs.io/) |
| btrbk | [digint.ch/btrbk](https://digint.ch/btrbk/) |
| Best of Nix | [github.com/tolkonepiu/best-of-nix](https://github.com/tolkonepiu/best-of-nix) — curated tools and libraries |
