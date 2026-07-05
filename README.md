# knirski/nix-config

<p>
  <a href="https://nixos.org"><img src="https://img.shields.io/badge/NixOS-26.05-5277C3?logo=nixos&logoColor=white" alt="NixOS"></a>
  <a href="https://nixos.wiki/wiki/Flakes"><img src="https://img.shields.io/badge/flakes-enabled-7eb6e0?logo=nixos&logoColor=white" alt="Flakes"></a>
  <a href="https://flake.parts"><img src="https://img.shields.io/badge/built%20with-flake--parts-7eb6e0" alt="flake-parts"></a>
  <a href="https://flake.parts"><img src="https://img.shields.io/badge/pattern-dendritic-7eb6e0" alt="dendritic"></a>
  <a href="https://github.com/oddlama/nix-topology"><img src="https://img.shields.io/badge/diagrams-nix--topology-7eb6e0" alt="nix-topology"></a>
  <a href="https://github.com/knirski/nix-config/actions/workflows/ci.yml"><img src="https://github.com/knirski/nix-config/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
</p>

Multi-host [NixOS](https://nixos.org) flake built with [flake-parts](https://flake.parts)
and the [dendritic](https://flake.parts) pattern.

## Hosts

| Host | Role |
| ---- | ---- |
| **Soyo** (Intel N150) | LAN DNS + DHCP appliance, 16 GB, single Gigabit NIC |

## Quick start

```bash
./scripts/deploy-soyo.sh
# Or manually: nixos-rebuild switch --flake .#soyo --target-host krzysiek@soyo --sudo
# If DNS isn't working: nixos-rebuild switch --flake .#soyo --target-host krzysiek@10.0.0.9 --sudo
```

For a first install from the NixOS live ISO, see [docs/install-soyo.md](docs/install-soyo.md).
For the condensed checklist, see [hosts/soyo/DEPLOY.md](hosts/soyo/DEPLOY.md).

For the guided learning path through this repo, start at [docs/learning/README.md](docs/learning/README.md).

## Structure

```text
├── hosts/<name>/          # Per-host hardware data (facter.json, disko, networking, …)
├── modules/
│   ├── nixos/             # Reusable NixOS aspect modules (base, blocky, dhcp, …)
│   ├── home/              # Reusable Home Manager aspect modules
│   └── parts/             # flake-parts modules: assemblers, options
├── secrets/               # agenix-encrypted secrets + recipients (see docs/secrets.md)
├── docs/                  # Design spec, plans, and learning docs
└── flake.nix              # Entry point — auto-imports modules/
```

Aspect modules are listed in `modules/default.nix`, expose `aspects.nixos.<name>`,
and are toggled in the host assembler (`modules/parts/soyo.nix`).
Host directories hold machine-specific data only.

## Design

The canonical design document is
[docs/superpowers/specs/soyo-dns-dhcp-appliance.md](docs/superpowers/specs/soyo-dns-dhcp-appliance.md).

Key principles:

- **DNS + DHCP only** — everything else is a guest service, resource-isolated.
- **Impermanent root** — `/` is wiped to a blank Btrfs snapshot each boot; durable state is restored from an explicit persisted-path inventory under `/persist`, including private `DynamicUser` state when services store it under `/var/lib/private`.
- **Secrets via agenix-rekey** — master-encrypted files rekeyed per host. Full walkthrough in [docs/secrets.md](docs/secrets.md).
- **`linuxPackages_latest`** — the in-tree `dwmac_motorcomm` NIC driver (Linux 6.13+).
- **TPM auto-unlock** — unattended power-loss recovery; passphrase keyslot as break-glass fallback.
- **Tailscale mesh VPN** — remote admin from anywhere, no open ports, no DynDNS. Auth key deployed as an encrypted agenix secret.
- **On-box observability** — Grafana, Prometheus, Loki, Tempo, and Alloy run as resource-isolated guest services; Grafana/Loki/Tempo/Prometheus persist under `/var/lib/<name>`, while Alloy's journal cursor persists under `/var/lib/private/alloy`.

## Tooling

```bash
# CI (runs on every push via GitHub Actions)
# Lint: deadnix, statix, typos, gitleaks, actionlint, shellcheck,
#       markdownlint, ruff (gitleaks uses --config .gitleaks.toml)
# https://github.com/knirski/nix-config/actions

# Generate network topology diagram
nix build .#topology.x86_64-linux.config.output
# open result/main.svg

# Build with real-time progress
nom build .#nixosConfigurations.soyo.config.system.build.toplevel

# Find which package provides a missing command
nix-locate <command>

# Connect remotely via Tailscale
ssh krzysiek@soyo

# Check for CVEs in the current system closure
# (requires vulnix: nix shell nixpkgs#vulnix)
sudo nix-shell -p vulnix --run 'vulnix -c system'
```

## Requirements

- Nix 2.18+ with flakes enabled (`nix-command flakes` experimental features)
- NixOS 26.05 (nixpkgs `release-26.05` branch)

## Resources

- [Best of Nix](https://github.com/tolkonepiu/best-of-nix) — curated list of Nix & NixOS tools, libraries, and resources
