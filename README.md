# knirski/nix-config

<p>
  <a href="https://nixos.org"><img src="https://img.shields.io/badge/NixOS-26.05-5277C3?logo=nixos&logoColor=white" alt="NixOS"></a>
  <a href="https://nixos.wiki/wiki/Flakes"><img src="https://img.shields.io/badge/flakes-enabled-7eb6e0?logo=nixos&logoColor=white" alt="Flakes"></a>
  <a href="https://flake.parts"><img src="https://img.shields.io/badge/built%20with-flake--parts-7eb6e0" alt="flake-parts"></a>
  <a href="https://flake.parts"><img src="https://img.shields.io/badge/pattern-dendritic-7eb6e0" alt="dendritic"></a>
  <a href="https://github.com/oddlama/nix-topology"><img src="https://img.shields.io/badge/diagrams-nix--topology-7eb6e0" alt="nix-topology"></a>
  <a href="https://github.com/knirski/nix-config/actions/workflows/ci.yml"><img src="https://github.com/knirski/nix-config/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
</p>

Multi-host [NixOS](https://nixos.org) flake for a LAN DNS/DHCP appliance (Soyo) and a
desktop/gaming workstation (zbook). Built with [flake-parts](https://flake.parts) and the
[dendritic pattern](https://flake.parts): reusable aspect modules live under `modules/`, host-specific
data under `hosts/<name>/`.

This is also a **learning project** — the repo is intentionally documented to teach modern Nix
idioms. Start at [docs/learning/README.md](docs/learning/README.md) for the guided path.

## Hosts

| Host | Hardware | Role |
| ---- | -------- | ---- |
| **Soyo** | Intel N150, 16 GB, Gigabit NIC | LAN DNS (Blocky) + DHCP (dnsmasq), on-box observability (Grafana/Prometheus/Loki/Tempo) |
| **zbook** | HP ZBook Studio 16" G10, 32 GB, NVIDIA RTX 4000 Ada | Desktop (COSMIC), gaming (Steam/Gamescope), NVIDIA Optimus |

## Quick start

```bash
# Enter dev shell with all tooling
nix develop

# Deploy to a host (deploy-rs with magic rollback)
deploy .#soyo
deploy .#zbook

# Or directly via SSH
nixos-rebuild switch --flake .#soyo --target-host krzysiek@soyo --sudo

# Run the health check after deployment
nix run .#healthcheck soyo 10.0.0.9

# Generate network topology diagram
nix build .#topology.x86_64-linux
```

For first install from a NixOS live ISO, see [docs/install-soyo.md](docs/install-soyo.md)
or [hosts/zbook/INSTALL.md](hosts/zbook/INSTALL.md).

## Structure

```text
├── flake.nix                    # Entry point — delegates to modules/
├── modules/
│   ├── default.nix              # Module registry — every file listed here
│   ├── nixos/                   # NixOS aspect modules (toggleable features)
│   │   ├── ssh.nix              #   Shared: OpenSSH lockdown (key-only)
│   │   ├── server.nix           #   Soyo: systemd-networkd + earlyoom
│   │   ├── tailscale.nix        #   Shared: Tailscale auth oneshot
│   │   ├── backup.nix           #   Shared: restic + btrbk
│   │   ├── base.nix             #   Shared: timezone, locale, packages
│   │   ├── users.nix            #   Shared: mutableUsers=false, agenix secrets
│   │   ├── persistence.nix      #   Shared: impermanent root rollback
│   │   ├── blocky.nix           #   Soyo: DNS resolver
│   │   ├── dhcp.nix             #   Soyo: dnsmasq DHCP
│   │   ├── remote-unlock.nix    #   Soyo: initrd SSH unlock
│   │   ├── maintenance.nix     #   Shared: nix gc, scrub, smartd, ntfy
│   │   ├── observability.nix   #   Soyo: Grafana/Prometheus/Loki/Tempo
│   │   ├── desktop.nix          #   zbook: PipeWire, Bluetooth, fonts
│   │   ├── cosmic.nix           #   zbook: COSMIC desktop environment
│   │   ├── nvidia.nix           #   zbook: NVIDIA Optimus PRIME
│   │   ├── laptop.nix           #   zbook: power-profiles-daemon, thermald
│   │   ├── gaming.nix           #   zbook: Steam, Gamescope, MangoHud
│   │   └── workstation.nix      #   zbook: semantic marker
│   ├── home/                    # Home Manager aspects
│   │   ├── base.nix             #   Shared: bash, git, direnv, command-code
│   │   └── desktop.nix          #   zbook: COSMIC theme, media tools
│   └── parts/                   # flake-parts modules
│       ├── aspect-options.nix   #   Defines the aspects.* namespace
│       ├── soyo.nix             #   Assembles nixosConfigurations.soyo
│       ├── zbook.nix            #   Assembles nixosConfigurations.zbook
│       ├── perSystem.nix        #   Dev shell, formatter, pre-commit hooks
│       ├── deploy.nix           #   deploy-rs nodes
│       └── topology.nix         #   nix-topology diagrams
├── hosts/<name>/                # Per-host data only (hardware, networking, secrets)
├── lib/observability/           # Grafana dashboard builders, Alloy config, Tempo traces
├── secrets/                     # agenix-rekey encrypted secrets
├── docs/                        # Design docs, learning path, runbooks
└── scripts/                     # Health check, secret recovery utilities
```

Aspects are composed in each host assembler (`modules/parts/<host>.nix`)
by listing them by name:

```nix
modules = (with config.aspects.nixos; [
  base  ssh  server  tailscale  users  persistence  … # shared
  remote-unlock  blocky  dhcp  backup  observability   # Soyo-only
]);
```

No file-path imports across aspect modules — just declarative toggles.

## Design principles

- **DNS + DHCP are the only critical roles** — every other service is a resource-isolated guest.
- **Impermanent root** — `/` is wiped to a blank Btrfs snapshot each boot; durable state lives under `/persist`.
- **Secrets via agenix-rekey** — master-encrypted files rekeyed per host. Full walkthrough in [docs/secrets.md](docs/secrets.md).
- **Role-neutral base** — `modules/nixos/base.nix` and `modules/home/base.nix` carry no networking, swap, or display assumptions.
- **Thin hosts, fat modules** — all reusable logic is in aspect modules; host directories hold only hardware data.
- **Single source of truth** — `hosts/soyo/reservations.nix` drives DHCP, DNS forward/reverse, topology diagrams, and observability probes.
- **TPM auto-unlock** — unattended power-loss recovery with passphrase break-glass fallback.
- **On-box observability** — Grafana, Prometheus, Loki, Tempo, and Alloy as isolated guest services on Soyo.
- **Tailscale mesh VPN** — remote admin from anywhere, no open ports. Auth key deployed as agenix secret.
- **Automatic CI** — lint (deadnix, statix, typos, gitleaks) → eval (`nix flake check`) → build → topology on every push.

The canonical design document is
[docs/superpowers/specs/soyo-dns-dhcp-appliance.md](docs/superpowers/specs/soyo-dns-dhcp-appliance.md).

## Tooling

```bash
# Enter dev shell
nix develop

# Deploy to a host
deploy .#<hostname>

# CI (runs on every push via GitHub Actions)
# https://github.com/knirski/nix-config/actions

# Build with real-time progress
nom build .#nixosConfigurations.soyo.config.system.build.toplevel

# Find which package provides a missing command
nix-locate <command>

# Connect remotely via Tailscale
ssh krzysiek@soyo

# Check for CVEs in the current system closure
sudo nix-shell -p vulnix --run 'vulnix -c system'

# Run pre-commit hooks on all files
nix develop -c pre-commit run --all-files
```

## Requirements

- Nix 2.18+ with flakes enabled (`nix-command` and `flakes` experimental features)
- NixOS 26.05 (nixpkgs `release-26.05` branch) or later

## Resources

- [docs/learning/README.md](docs/learning/README.md) — guided 37-step learning path
- [docs/superpowers/specs/soyo-dns-dhcp-appliance.md](docs/superpowers/specs/soyo-dns-dhcp-appliance.md) — canonical design document
- [docs/secrets.md](docs/secrets.md) — agenix-rekey walkthrough for beginners
- [AGENTS.md](AGENTS.md) — hard invariants, workflow, and contributor rules
- [Best of Nix](https://github.com/tolkonepiu/best-of-nix) — curated Nix/NixOS tools and resources
