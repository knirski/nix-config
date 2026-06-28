# AGENTS.md — guidelines and guardrails for this repo

A multi-host NixOS flake. First host: **Soyo** (Intel N150), a LAN DNS + DHCP
appliance. Future hosts (e.g. a gaming laptop) layer on the same base.

**Read first:** [`docs/superpowers/specs/soyo-dns-dhcp-appliance.md`](docs/superpowers/specs/soyo-dns-dhcp-appliance.md)
is the canonical design — decisions, hardware facts, the M1–M4 roadmap, and an
alternatives appendix. This file is the short rulebook; the design doc is the why.

This is also a **learning project**: idiomatic Nix/NixOS from basics. The code
and its docs must teach (see "Learning docs" below).

## Hard invariants (do not violate without an explicit decision in the design doc)

1. **DNS and DHCP are the only critical roles.** Everything else is a guest.
   Never let another service compromise them.
2. **Guest services are opt-in and resource-isolated** — systemd `MemoryMax`,
   `CPUQuota`, lowered `Nice`/`IOWeight`. Limits constrain, not guarantee; a
   genuinely heavy workload belongs on another host, not Soyo.
3. **`modules/base` and `modules/home/base.nix` stay role-neutral** — no network
   backend, no swap policy, no GUI/display assumptions. Role-specific config
   lives in a role module or the host.
4. **Kernel is pinned to Linux 6.12 LTS** for the out-of-tree `yt6801` NIC
   module. Do not bump it blind: after any change, confirm the module builds and
   `enp1s0` comes up. Unpin only when the in-tree `yt6801` lands
   (`drivers/net/ethernet/motorcomm/yt6801/` present in the running kernel).
5. **Secrets via agenix only.** Never commit plaintext secrets; passwords are
   hashed-password secrets. MAC/IP addresses are *not* secrets (plaintext fine).
6. **DNS ownership is split:** Blocky owns forward A records; dnsmasq owns
   reverse/PTR (lease-aware, Blocky forwards the reverse zone to it). Static
   hosts come from `hosts/soyo/reservations.nix` — the single source of truth.
7. **TPM unlock phasing:** Phase 1 binds PCR 7 (no Secure Boot); Phase 2 binds
   PCR 0+2+7 with Limine Secure Boot. Never bind PCR 9 (kernel image) or PCR 8
   (store paths) — they break unattended auto-unlock. Always keep the passphrase
   keyslot as fallback.
8. **flake-parts + explicit role modules.** Not the dendritic pattern. Hosts
   compose by explicit `imports`; each host file plainly lists what it is.
9. **Reproducible + recoverable.** Everything declarative; persistent state is
   tracked under the `persist` subvolume and backed up (restic → Synology). No
   impermanence. Do not break TPM auto-unlock or the break-glass paths
   (local console, LAN initrd SSH, direct-link rescue).

## Anti-goals (keep off Soyo)

- local LLM inference (no usable GPU, fixed 16 GB) — API-based agents are fine
- ZFS, impermanence, NetworkManager on the server
- WAN-inbound services — reach in via Tailscale
- CPU-bursty workloads (game servers, CI runners, heavy DBs)

## Adding a service

1. Prefer a native NixOS module (e.g. `services.jellyfin`); a container only
   where no module exists.
2. Own module under `modules/nixos/services/<name>.nix`, opt-in per host.
3. Resource-isolate it (invariant 2).
4. Give it a `home.arpa` name via Blocky; put a reverse proxy (Caddy, internal
   TLS) in front once there is more than one web service.
5. Back up its state as class 3 (restic). Bulk data lives on the NAS over NFS.
6. Reassess RAM/CPU headroom and the widened outage blast radius.

## Adding a host

- `hosts/<name>/` with its own `boot.nix`, `disko.nix`, `networking.nix`.
- Reuse `modules/base`, `modules/nixos/users`, `modules/home/base.nix`, the
  backup module, the disko pattern. Do **not** import server-only modules
  (DNS, DHCP, remote-unlock) on a non-server host.
- New agenix host key + recipient + rekey for any secrets it needs.

## Learning docs (required output)

- Comment modules with the *why* and the idiom, not just the *what*.
- Introduce one concept at a time along the M1–M4 roadmap.
- When a concept first appears, explain it briefly and link a canonical source:
  [nix.dev](https://nix.dev), the [NixOS](https://nixos.org/manual/nixos/stable/)
  and [Nixpkgs](https://nixos.org/manual/nixpkgs/stable/) manuals,
  [Home Manager](https://nix-community.github.io/home-manager/),
  [flake.parts](https://flake.parts),
  [search.nixos.org](https://search.nixos.org/options).
- Readability over cleverness — it is part of the deliverable.

## Workflow

- Build order follows the design doc's roadmap; M1 + M2 are the production
  cut-line, M3 hardens (Secure Boot), M4 expands (laptop, services).
- Rehearse host build + disk layout in a VM (`nixos-rebuild build-vm`, disko VM
  test) before touching hardware.
- Before committing: `treefmt` (format), `deadnix` (lint), `nix flake check`.
- Keep host directories thin; push reusable logic into modules.
- Run the design doc's validation checklist after changes that touch boot,
  unlock, networking, or services.
