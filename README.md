# knirski/nix-config

Multi-host [NixOS](https://nixos.org) flake built with [flake-parts](https://flake.parts)
and the [dendritic](https://github.com/vic/import-tree) pattern.

## Hosts

| Host | Role |
|------|------|
| **Soyo** (Intel N150) | LAN DNS + DHCP appliance, 16 GB, single Gigabit NIC |

## Quick start

```bash
nixos-rebuild switch --flake .#soyo --target-host krzysiek@10.0.0.9 --use-remote-sudo
```

For a first install from the NixOS live ISO, see [hosts/soyo/DEPLOY.md](hosts/soyo/DEPLOY.md).

## Structure

```
├── hosts/<name>/          # Per-host hardware data (facter.json, disko, networking, …)
├── modules/
│   ├── nixos/             # Reusable NixOS aspect modules (base, blocky, dhcp, …)
│   ├── home/              # Reusable Home Manager aspect modules
│   └── parts/             # flake-parts modules: assemblers, options
├── secrets/               # agenix-encrypted secrets + recipients (see docs/secrets.md)
├── docs/                  # Design spec, plans, and learning docs
└── flake.nix              # Entry point — auto-imports modules/
```

Aspect modules expose `flake.modules.nixos.<name>` and are toggled in the host
assembler (`modules/parts/soyo.nix`). Host directories hold machine-specific
data only.

## Design

The canonical design document is
[docs/superpowers/specs/soyo-dns-dhcp-appliance.md](docs/superpowers/specs/soyo-dns-dhcp-appliance.md).

Key principles:

- **DNS + DHCP only** — everything else is a guest service, resource-isolated.
- **Impermanent root** — `/` is wiped to a blank Btrfs snapshot each boot; durable state lives under `/persist`.
- **Secrets via agenix-rekey** — master-encrypted files rekeyed per host. Full walkthrough in [docs/secrets.md](docs/secrets.md).
- **`linuxPackages_latest`** — the in-tree `dwmac_motorcomm` NIC driver (Linux 6.13+).
- **TPM auto-unlock** — unattended power-loss recovery; passphrase keyslot as break-glass fallback.

## Requirements

- Nix 2.18+ with flakes enabled (`nix-command flakes` experimental features)
- NixOS 26.05 (nixpkgs `714a5f8c4ead`)
