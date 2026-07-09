# knirski/nix-config

<p>
  <a href="https://nixos.org"><img src="https://img.shields.io/badge/NixOS-26.05-5277C3?logo=nixos&amp;logoColor=white" alt="NixOS"></a>
  <a href="https://nixos.wiki/wiki/Flakes"><img src="https://img.shields.io/badge/flakes-enabled-7eb6e0?logo=nixos&amp;logoColor=white" alt="Flakes"></a>
  <a href="https://flake.parts"><img src="https://img.shields.io/badge/built%20with-flake--parts-7eb6e0" alt="flake-parts"></a>
  <a href="https://github.com/mightyiam/dendritic"><img src="https://img.shields.io/badge/pattern-dendritic-7eb6e0" alt="dendritic"></a>
  <a href="https://github.com/oddlama/nix-topology"><img src="https://img.shields.io/badge/diagrams-nix--topology-7eb6e0" alt="nix-topology"></a>
  <a href="https://github.com/knirski/nix-config/actions/workflows/ci.yml"><img src="https://github.com/knirski/nix-config/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
</p>

Multi-host [NixOS](https://nixos.org) flake for a LAN DNS+DHCP appliance (**Soyo**) and a desktop/gaming workstation (**zbook**). Built with [flake-parts](https://flake.parts), auto-imported via [import-tree](https://github.com/vic/import-tree) after the [dendritic pattern](https://github.com/mightyiam/dendritic) — every file under `modules/` is a flake-parts module, and hosts assemble by toggling aspects by name.

This is also a **learning project**: the code and its docs intentionally teach modern Nix idioms. Start at [**docs/learning/README.md**](docs/learning/README.md) for a 37-step guided path from zero to understanding the whole flake.

## Hosts

| Host     | Hardware                                                                                | Role                     |
|----------|-----------------------------------------------------------------------------------------|--------------------------|
| **Soyo** | Intel N150, 16 GB, 512 GB NVMe, Gigabit NIC                                            | LAN DNS + DHCP appliance |
| **zbook**| HP ZBook Studio 16" G10, 32 GB, NVIDIA RTX 4000 Ada, 2 TB NVMe                        | COSMIC workstation       |

## Architecture — the dendritic pattern

Every `.nix` file under `modules/` (except `_`-prefixed paths) is **auto-imported as a flake-parts module** by [vic/import-tree](https://github.com/vic/import-tree). Adding a new module requires **zero registry edits** — just create the file.

```text
modules/
├── nixos/          NixOS aspect modules (toggleable features)
├── home/           Home Manager aspect modules
├── parts/          flake-parts infrastructure (host assemblers, dev shell, deploy, topology)
└── _pkgs/          Package definitions (callPackage files, skipped by import-tree)
```

Each aspect module sets `aspects.nixos.<name> = { … }` (or `aspects.homeManager.<name>`) and declares host-data options under `lanAppliance.services.<name>`.

Host **assemblers** (`modules/parts/soyo.nix`, `modules/parts/zbook.nix`) toggle aspects by name:

```nix
modules = (with config.aspects.nixos; [
  base  ssh  server  tailscale  users  persistence   # shared
  remote-unlock  blocky  dhcp  backup  observability # Soyo-only
]);
```

Host-specific **data** lives in thin files under `hosts/<name>/` — disko layout, networking, persistence inventory, backup targets, reservations. No reusable logic lives there.

## Key concepts

**Impermanence (erase-your-darlings).** Root is wiped to a blank Btrfs snapshot every boot. Only explicitly declared paths under `/persist` survive. The inventory is in `hosts/<name>/persistence.nix`.

**Secrets via agenix-rekey `rekeyFile`.** Master-encrypted `.age` files are rekeyed per host at build time. Each host decrypts with its own SSH host key (read from `/persist`, which is `neededForBoot`). Walkthrough: [docs/secrets.md](docs/secrets.md).

**TPM2 auto-unlock.** LUKS2 key enrolled against TPM PCRs 0+2+7 (Secure Boot state) with passphrase keyslot as break-glass. Unattended power-loss recovery.

**Single source of truth.** `hosts/soyo/reservations.nix` (a `{name,mac,ip}` list) drives Blocky forward-A records, dnsmasq DHCP reservations and PTR records, nix-topology diagrams, and observability blackbox probes.

**Network topology.** Generated from the reservation list by [nix-topology](https://github.com/oddlama/nix-topology). Render with `just topology` → [docs/topology/main.svg](docs/topology/main.svg).

**deploy-rs.** Remote deploys with auto-rollback and magic rollback. `deploy .#hostname` or `nixos-rebuild --target-host` as fallback.

**Tailscale mesh VPN.** Every host auto-authenticates via an agenix-encrypted auth key. SSH in from anywhere via `ssh krzysiek@<host>`.

## Structure

```text
├── flake.nix                     Entry point — declares inputs, delegates to import-tree
├── flake.lock                    Pinned inputs (updated via Renovate)
├── justfile                      Task runner — just lint, just check, just deploy <host>, …
├── renovate.json                 Automated flake input updates
├── AGENTS.md                     Hard invariants and contributor rules
├── modules/
│   ├── nixos/                    NixOS aspect modules (18 files)
│   │   ├── base.nix              Shared: timezone, locale, packages, command-code overlay
│   │   ├── ssh.nix              Shared: OpenSSH key-only lockdown
│   │   ├── server.nix            Soyo: systemd-networkd, earlyoom
│   │   ├── tailscale.nix         Shared: Tailscale auth oneshot
│   │   ├── users.nix            Shared: mutableUsers=false, agenix user secrets
│   │   ├── persistence.nix      Shared: impermanent root blank-snapshot rollback
│   │   ├── backup.nix            Shared: restic + btrbk
│   │   ├── maintenance.nix      Shared: nix gc, Btrfs scrub, SMART, ntfy alerts
│   │   ├── blocky.nix            Soyo: DNS resolver with ad-blocking
│   │   ├── dhcp.nix              Soyo: dnsmasq DHCP + reverse DNS
│   │   ├── remote-unlock.nix     Soyo: initrd SSH unlock + direct-link rescue
│   │   ├── observability.nix    Soyo: Grafana/Prometheus/Loki/Tempo/Alloy stack
│   │   ├── desktop.nix           zbook: PipeWire, Bluetooth, Flatpak, fonts
│   │   ├── cosmic.nix            zbook: COSMIC DE + greeter, NVIDIA suspend hooks
│   │   ├── nvidia.nix            zbook: NVIDIA Optimus PRIME offload/sync
│   │   ├── laptop.nix            zbook: power-profiles-daemon, thermald, usbcore.quirks
│   │   ├── gaming.nix            zbook: Steam, Gamescope, MangoHud, Lutris
│   │   └── workstation.nix      zbook: semantic marker
│   ├── home/
│   │   ├── base.nix              Shared: bash, git, direnv, command-code
│   │   └── desktop.nix           zbook: Catppuccin COSMIC theme, media tools
│   ├── parts/
│   │   ├── aspect-options.nix   Defines aspects.nixos/homeManager namespaces
│   │   ├── perSystem.nix         Dev shell, formatter, pre-commit hooks, checks
│   │   ├── soyo.nix              Soyo host assembler
│   │   ├── zbook.nix              zbook host assembler
│   │   ├── deploy.nix            deploy-rs nodes + deployChecks
│   │   └── topology.nix          nix-topology diagram builder
│   └── _pkgs/
│       └── command-code.nix      Command Code CLI package (callPackage, not a module)
├── hosts/
│   ├── soyo/                      Soyo hardware/data (disko, boot, networking, dns, dhcp, …)
│   └── zbook/                      zbook hardware/data (disko, boot, networking, backup)
├── lib/observability/             Dashboard builders, Alloy config, Tempo traces (plain Nix functions)
├── secrets/                       agenix-rekey master-encrypted .age files + host pubkeys
├── docs/                          Design docs, learning path, install/backup/recovery runbooks
├── scripts/                       healthcheck.sh, recover-secrets.sh, set-tailscale-keys.sh
└── .github/workflows/             CI: lint → eval → build → topology
```

## Quick start

```bash
# Clone and enter dev shell
git clone https://github.com/knirski/nix-config ~/.setup && cd ~/.setup
nix develop          # installs pre-commit hooks automatically

# Common tasks (using just, the task runner)
just                 # list all available recipes
just lint            # format + static analysis
just check           # nix flake check (eval + build + deploy checks + option tests)
just test            # run dendritic option-namespace tests
just build soyo      # build soyo's system closure
just deploy soyo     # deploy Soyo with deploy-rs (auto-rollback + magic rollback)
just topology        # generate LAN topology diagrams
just healthcheck soyo # run on-host health check over SSH

# Without just:
nix flake check
nix build .#nixosConfigurations.soyo.config.system.build.toplevel
nix run .#healthcheck -- soyo
deploy .#zbook       # from inside nix develop
nixos-rebuild switch --flake .#zbook --target-host krzysiek@zbook --sudo  # fallback

# After deploy, run the automated health check
nix run .#healthcheck soyo
```

For first install from a NixOS live ISO, see **[docs/install-soyo.md](docs/install-soyo.md)** or **[hosts/zbook/INSTALL.md](hosts/zbook/INSTALL.md)**.

## Adding a new aspect

1. Create a file under `modules/nixos/` (e.g. `modules/nixos/jellyfin.nix`).
2. Set `aspects.nixos.jellyfin = { lib, config, ... }: { … }` with host-data options under `lanAppliance.services.jellyfin`.
3. Toggle `jellyfin` in the host assembler's `with config.aspects.nixos; [ … ]` list.

No registry edits — import-tree auto-discovers every new `.nix` file.

## Adding a new host

1. Create `hosts/<name>/` with `facter.json`, `disko.nix`, `boot.nix`, `networking.nix`, and an optional `users.nix` and `backup.nix`.
2. Create `modules/parts/<name>.nix` — an assembler toggling aspects and importing host data.
3. Add `modules/parts/<name>.nix` to auto-import scope (already done — it's under `modules/`).
4. Generate an SSH host key, save public key as `secrets/<name>.pub`, set `age.rekey.hostPubkey` in the assembler, run `agenix rekey`.
5. Add `<name>` to the CI build matrix in `.github/workflows/ci.yml`.

## Design principles

**DNS and DHCP are the only critical roles.** Every other service is a resource-isolated guest (`MemoryMax`, `CPUQuota`, lowered `Nice`).

**Impermanent root.** Declared durable state only — forces an inventory of what matters.

**Role-neutral base.** `modules/nixos/base.nix` and `modules/home/base.nix` carry no networking, swap, or display assumptions.

**Thin hosts, fat modules.** All reusable logic is in aspect modules; host directories hold only hardware data.

**TPM auto-unlock.** PCR 0+2+7 binding with Limine Secure Boot; passphrase keyslot always present as fallback.

**On-box observability.** Grafana, Prometheus, Loki, Tempo, and Alloy run as isolated guest services on Soyo with hand-built dashboards.

**Automatic CI.** Lint (deadnix, statix, typos, gitleaks, shellcheck, markdownlint, ruff) → `nix flake check` → build (soyo + zbook) with closure diff → topology artifact.

**Everything declarative.** Hardware via `nixos-facter`, not `nixos-generate-config`. Backup targets, DNS records, DHCP reservations — all in Nix.

## Tooling

| Tool | Purpose |
|------|---------|
| [nixfmt](https://github.com/NixOS/nixfmt) | Nix formatter (via treefmt) |
| [deadnix](https://github.com/astro/deadnix) | Find dead Nix code |
| [statix](https://github.com/nerdypepper/statix) | Nix linting |
| [typos](https://github.com/crate-ci/typos) | Spell checker |
| [ruff](https://github.com/astral-sh/ruff) | Python linter |
| [shellcheck](https://www.shellcheck.net) | Shell script analyzer |
| [markdownlint](https://github.com/DavidAnson/markdownlint) | Markdown style checker |
| [import-tree](https://github.com/vic/import-tree) | Auto-import every module file |
| [deploy-rs](https://github.com/serokell/deploy-rs) | Remote deployment with rollback |
| [nix-topology](https://github.com/oddlama/nix-topology) | Infrastructure diagrams |
| [Renovate](https://docs.renovatebot.com) | Automated flake.lock updates |
| [just](https://github.com/casey/just) | Command runner |

## Key docs

| Document | What it covers |
|----------|---------------|
| [docs/learning/README.md](docs/learning/README.md) | 37-step guided path from zero to understanding the whole flake |
| [docs/superpowers/specs/soyo-dns-dhcp-appliance.md](docs/superpowers/specs/soyo-dns-dhcp-appliance.md) | Canonical design — every architectural decision and why |
| [docs/secrets.md](docs/secrets.md) | agenix-rekey walkthrough for beginners |
| [docs/install-soyo.md](docs/install-soyo.md) | First-install runbook for Soyo |
| [docs/backup-and-restore.md](docs/backup-and-restore.md) | restic restore drill + btrbk snapshot recovery |
| [docs/recovery.md](docs/recovery.md) | Break-glass recovery procedures |
| [docs/update-and-rollback.md](docs/update-and-rollback.md) | `nix flake update` + `deploy-rs` rollback |
| [AGENTS.md](AGENTS.md) | Hard invariants, anti-goals, workflow rules |

## Requirements

- [Nix](https://nixos.org/download/) 2.18+ with `experimental-features = nix-command flakes`
- NixOS 26.05 (Soyo) or nixpkgs-unstable (zbook)

## Acknowledgments

- [mightyiam/dendritic](https://github.com/mightyiam/dendritic) — the pattern that shaped this repo's architecture
- [vic/import-tree](https://github.com/vic/import-tree) — zero-boilerplate module auto-discovery
- [flake.parts](https://flake.parts) — modular flake outputs
- [Best of Nix](https://github.com/tolkonepiu/best-of-nix) — curated Nix/NixOS tools and resources
