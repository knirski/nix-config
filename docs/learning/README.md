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
| 6 | `flake.nix` → `modules/default.nix` | M1 | The entry point — thin, delegates to flake-parts; `modules/default.nix` explicitly lists every module |
| 7 | `modules/parts/soyo.nix` | M1 | How a host is assembled by toggling aspects |
| 8 | `modules/nixos/base.nix` → `server.nix` → `users.nix` | M1 | The role-neutral base, server-only defaults, user policy |
| 9 | `modules/nixos/persistence.nix`, `hosts/soyo/persistence.nix` | M1 | Impermanence via blank-snapshot rollback + the concrete persisted-path inventory, including why boot signing state like `/var/lib/sbctl` belongs in it |
| 10 | `modules/nixos/blocky.nix`, `hosts/soyo/dns.nix` | M1 | DNS with blocking (Blocky) |
| 11 | `modules/nixos/dhcp.nix`, `hosts/soyo/dhcp.nix` | M1 | DHCP + reverse DNS (dnsmasq) |
| 12 | `modules/nixos/remote-unlock.nix`, `hosts/soyo/initrd-unlock.nix` | M1 | TPM auto-unlock + break-glass paths |
| 13 | [agenix/agenix-rekey](https://github.com/ryantm/agenix), `docs/secrets.md` | M1 | Encrypted secrets, rekeyFile flow |
| 14 | `modules/nixos/maintenance.nix` | M2 | Scheduled upkeep: gc, scrub, SMART, ntfy alerts |
| 15 | `modules/nixos/backup.nix`, `hosts/soyo/backup.nix` | M2 | restic to Synology, btrbk local snapshots |
| 16 | `modules/nixos/observability.nix`, `lib/observability/`, `hosts/soyo/observability.nix`, [`docs/topology/`](../topology/) | M2 | Exporters, on-box Grafana, Loki logs, Tempo traces, Alloy journal shipping. Reusable helpers extracted to `lib/observability/` (outside `import-tree`'s scope — see comment in the module). LAN observability adds passive inventory collector (`modules/nixos/observability/lan_inventory.py`), blackbox probes (ICMP + HTTP), an `LAN Overview` dashboard, and topology diagrams under `docs/topology/`. Host-local network metadata lives in `hosts/soyo/network.nix` (separated from the DHCP schema to keep the critical path boring). |
| 17 | `hosts/soyo/boot.nix` | M3 | Limine Secure Boot, TPM PCR binding, and Limine's `sbctl` signing model |
| 18 | `modules/parts/perSystem.nix` | All | Dev shell, formatter, pre-commit hooks (treefmt, deadnix, statix, typos, end-of-file-fixer, check-merge-conflicts, actionlint, shellcheck, markdownlint, ruff), CI pipeline |
| 19 | `modules/nixos/server.nix` (Tailscale section) | M2 | Tailscale mesh VPN, remote admin without open ports |
| 20 | [CI design doc](../superpowers/specs/2026-07-05-ci-pipeline-design.md), [CI plan](../superpowers/plans/2026-07-05-ci-pipeline-plan.md), `.github/workflows/ci.yml`, `modules/nixos/observability.nix` (Grafana alerts) | M2 | CI pipeline (lint: deadnix + statix + typos + gitleaks + actionlint + shellcheck + markdownlint + ruff → eval: `nix flake check` → build + closure diff → topology artifact), Grafana alerting (disk, backup, service health via ntfy), backup Prometheus metric |
| 21 | `modules/nixos/laptop.nix`, `modules/nixos/workstation.nix` | M4 | Laptop power management (tlp, battery thresholds) and workstation defaults (docker, ssh agent) |
| 22 | `modules/nixos/desktop.nix`, `modules/home/desktop.nix` | M4 | COSMIC desktop environment session, NixOS display-manager + HM user-config |
| 23 | `modules/nixos/nvidia.nix` | M4 | NVIDIA proprietary driver (RTX 4000 Ada), prime sync, offload modes |
| 24 | `modules/nixos/gaming.nix` | M4 | Steam, gamemode, MangoHud, game-specific tweaks |
| 25 | `modules/parts/zbook.nix`, `hosts/zbook/` | M4 | zbook host assembler — toggles laptop, workstation, desktop, nvidia, and gaming aspects onto the same base modules used by Soyo |
| 26 | Nvidia bug (this section) | M4 | The read-only `hardware.nvidia.enabled` trap; udev over systemd services for suspend wake |
| 27 | `modules/nixos/laptop.nix` — udev wake rules | M4 | Udev rules for USB/Thunderbolt ACPI wake, following nixos-hardware PR #1394 (udev over systemd oneshot) |

## What is this repo?

A NixOS flake that configures a small Intel N150 box ("Soyo") as a LAN DNS and DHCP appliance and an HP ZBook Studio G10 ("zbook") as a desktop/gaming workstation. The repository doubles as a deliberate way to learn modern Nix — see [Learning Goals](../superpowers/specs/soyo-dns-dhcp-appliance.md#learning-goals).

## Glossary

**Flake** — A self-contained Nix expression with locked inputs (`flake.lock`). Root is `flake.nix`.

**flake-parts** — A framework that splits a flake into composable modules. Each module can contribute to outputs (packages, checks, dev shells, NixOS configs).

**Dendritic pattern** — `modules/default.nix` explicitly lists every `.nix` file under `modules/` as a flake-parts module. Each file is one *aspect* (e.g. `blocky`, `dhcp`, `backup`) and contributes to a    shared namespace: `aspects.nixos.<aspect>`. A host is assembled by
   toggling aspects on, not by `imports` of file paths.

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

Each name in that list is an aspect contributed by a file under `modules/nixos/`. `modules/default.nix` lists every file explicitly. To add a new aspect, create a file under `modules/nixos/` that sets `aspects.nixos.<name>`, add it to `modules/default.nix`, then toggle it in the host assembler.

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

### Udev rules over systemd services for suspend wake

The zbook immediately woke from suspend when a USB-C dock (ethernet, monitor,
Logitech receiver) was connected. The first attempt used systemd oneshot
services to write to `/proc/acpi/wakeup` — but these had three problems:

1. **Race with powertop** — powertop's `--auto-tune` re-enables ACPI wake
   for some controllers after the service runs.
2. **Race with udev events** — hotplug events during boot can re-arm the
   ACPI wake state after the service has already disabled it.
3. **Needs resume hooks** — a separate service is needed after
   `suspend.target` in case the controller gets re-armed during resume.

The canonical approach (from [nixos-hardware PR #1394](https://github.com/NixOS/nixos-hardware/pull/1394)
and the [NixOS Wiki](https://wiki.nixos.org/wiki/Power_Management)) is
**udev rules targeting PCI subsystem IDs**. Udev rules fire at device-probe
time, survive device re-enumeration, and are automatically re-applied on
resume:

```nix
services.udev.extraRules = lib.mkAfter ''
  ACTION=="add", SUBSYSTEM=="pci", DRIVER=="xhci_hcd", ATTR{power/wakeup}="disabled"
  ACTION=="add", SUBSYSTEM=="pci", DRIVER=="thunderbolt", ATTR{power/wakeup}="disabled"
  ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0xa76e", ATTR{power/wakeup}="disabled"
'';
```

`lib.mkAfter` is used so nixos-hardware's own udev rules take precedence
(seen on the Framework 16 wiki). The three rule categories target:
- **`xhci_hcd` driver** — USB xHCI controllers (both internal USB and USB4 host)
- **`thunderbolt` driver** — USB4/Thunderbolt controllers
- **Specific device IDs** — PCIe root ports that can't be matched by driver
  name alone (e.g. non-Thunderbolt PCIe ports should preserve wake)

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
