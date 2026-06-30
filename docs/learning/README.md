# Learning Path — Soyo DNS/DHCP Appliance

A guided entry point for this repository's code and the Nix/NixOS concepts it uses. Read in order — each section builds on the last and maps to a milestone in the [Soyo design doc](../superpowers/specs/soyo-dns-dhcp-appliance.md).

## Reading order & roadmap

| # | Document | Milestone | What you'll learn |
|---|----------|-----------|-------------------|
| 1 | This README | — | Glossary, repo layout, dendritic wiring |
| 2 | [Nix language basics](https://nix.dev/tutorials/nix-language) (nix.dev) | — | The Nix expression language — read before the flake |
| 3 | [Flakes](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake) (Nix manual) | — | What a flake is, inputs/outputs |
| 4 | [flake-parts](https://flake.parts) | M1 | Modular flake outputs, perSystem |
| 5 | [Design doc](../superpowers/specs/soyo-dns-dhcp-appliance.md) | All | Every architectural decision and why |
| 6 | `flake.nix` | M1 | The entry point — thin, delegates to flake-parts + import-tree |
| 7 | `modules/parts/soyo.nix` | M1 | How a host is assembled by toggling aspects |
| 8 | `modules/nixos/base.nix` → `server.nix` → `users.nix` | M1 | The role-neutral base, server-only defaults, user policy |
| 9 | `modules/nixos/persistence.nix` | M1 | Impermanence via blank-snapshot rollback + preservation |
| 10 | `modules/nixos/blocky.nix`, `hosts/soyo/dns.nix` | M1 | DNS with blocking (Blocky) |
| 11 | `modules/nixos/dhcp.nix`, `hosts/soyo/dhcp.nix` | M1 | DHCP + reverse DNS (dnsmasq) |
| 12 | `modules/nixos/remote-unlock.nix`, `hosts/soyo/initrd-unlock.nix` | M1 | TPM auto-unlock + break-glass paths |
| 13 | [agenix/agenix-rekey](https://github.com/ryantm/agenix), `docs/secrets.md` | M1 | Encrypted secrets, rekeyFile flow |
| 14 | `modules/nixos/maintenance.nix` | M2 | Scheduled upkeep: gc, scrub, SMART, ntfy alerts |
| 15 | `modules/nixos/backup.nix`, `hosts/soyo/backup.nix` | M2 | restic to Synology, btrbk local snapshots |
| 16 | `modules/nixos/observability.nix`, `hosts/soyo/observability.nix` | M2 | Exporters on Soyo, dashboards off-box |
| 17 | `hosts/soyo/boot.nix` | M3 | Limine Secure Boot, TPM PCR binding |
| 18 | `modules/parts/perSystem.nix` | All | Dev shell, formatter, checks |

## What is this repo?

A NixOS flake that configures a small Intel N150 box ("Soyo") as a LAN DNS and DHCP appliance. Future hosts (gaming laptop, etc.) will layer on the same base modules. The repository doubles as a deliberate way to learn modern Nix — see [Learning Goals](../superpowers/specs/soyo-dns-dhcp-appliance.md#learning-goals).

## Glossary

**Flake** — A self-contained Nix expression with locked inputs (`flake.lock`). Root is `flake.nix`.

**flake-parts** — A framework that splits a flake into composable modules. Each module can contribute to outputs (packages, checks, dev shells, NixOS configs).

**Dendritic pattern** — Every file under `modules/` is auto-imported as a flake-parts module by `import-tree`. Each file is one *aspect* (e.g. `blocky`, `dhcp`, `backup`) and contributes to a shared namespace: `flake.modules.nixos.<aspect>`. A host is assembled by toggling aspects on, not by `imports` of file paths.

**Aspect module** — One file under `modules/nixos/` or `modules/home/` that exposes a toggleable feature. Convention: `{ flake.modules.nixos.<name> = { ... }; }` with an `options.lanAppliance.*` namespace for host data.

**Host assembler** — A flake-parts module (e.g. `modules/parts/soyo.nix`) that builds a `nixosConfiguration` by listing which aspects to toggle and importing host-specific data files.

**Host data file** — A plain NixOS module under `hosts/soyo/` that provides host-specific values (disko layout, networking, reservations, backup targets). Not an aspect — just data imported by the assembler.

**Impermanence (erase-your-darlings)** — The root filesystem is wiped to a blank Btrfs snapshot on every boot. Only explicitly declared paths under `/persist` survive. Forces an inventory of what state actually matters.

**preservation** — The NixOS module that manages the persisted-path inventory and bind-mounts `/persist` contents back into runtime paths.

**TPM2 auto-unlock** — The LUKS2 encryption key is enrolled against the TPM's Platform Configuration Registers (PCRs). If the measured boot hasn't changed, the TPM releases the key without a passphrase — so power loss recovers unattended.

**PCR (Platform Configuration Register)** — A TPM register that hashes boot components. If firmware, bootloader, or Secure Boot state changes, PCR values change and the TPM won't release the key — the passphrase fallback is used instead.

**rekeyFile** — agenix-rekey's flow: secrets are master-encrypted with the operator's key, then rekeyed per-host at deploy time. Each host gets its own copy encrypted with its SSH host key.

**home.arpa** — The IANA-reserved special-use domain for home networks (RFC 8375). Used as the local search domain instead of `.local` (reserved for mDNS) or a made-up TLD.

## How the dendritic pattern works

Given `hosts/soyo`, what's actually turned on? The answer is in `modules/parts/soyo.nix`:

```
modules = (with config.flake.modules.nixos; [
  base server users persistence remote-unlock blocky dhcp
  maintenance backup observability
]) ++ [ ... host data files ... ]
```

Each name in that list is an aspect contributed by a file under `modules/nixos/`. `import-tree` auto-discovers these files — no explicit import list. To add a new aspect, create a file under `modules/nixos/` that sets `flake.modules.nixos.<name>`, then toggle it in the host assembler.

## Canonical sources

| Topic | Link |
|---|---|
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
