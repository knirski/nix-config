# AGENTS.md — guidelines and guardrails for this repo

A multi-host NixOS flake.

| Host | Role | Status |
| ---- | ---- | ------ |
| **Soyo** (Intel N150) | LAN DNS + DHCP appliance, 16 GB | M1/M2 complete, M3 pending |
| **zbook** (HP ZBook Studio 16" G10) | Desktop/gaming workstation, 32 GB, NVIDIA RTX 4000 Ada | M4 in progress |

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
3. **`modules/nixos/base.nix` and `modules/home/base.nix` stay role-neutral** — no network
   backend, no swap policy, no GUI/display assumptions. Role-specific config
   lives in a role module or the host.
4. **Kernel follows `linuxPackages_latest`** (7.1.1+). The NIC uses the in-tree
   `dwmac_motorcomm` driver. Do not pin to an older kernel without confirming
   `enp1s0` comes up, and do not regress to the out-of-tree `yt6801` module
   unless a kernel regression forces it.
5. **Secrets via agenix-rekey (rekeyFile flow).** See [`docs/secrets.md`](docs/secrets.md)
   for the full walkthrough. Never commit plaintext secrets; passwords are
   hashed-password secrets. MAC/IP addresses are *not* secrets (plaintext fine).
   - Master-encrypted `.age` files live in `secrets/`.
   - Host-specific rekeyed files live in `secrets/rekeyed/<host>/`.
   - The master identity is the operator's SSH key (`secrets/krzysiek.age.pub`).
   - Each host's age public key is derived from its SSH host key at install time.
6. **DNS ownership is split:** Blocky owns forward A records; dnsmasq owns
   reverse/PTR (lease-aware, Blocky forwards the reverse zone to it). Static
   hosts come from `hosts/soyo/reservations.nix` — the single source of truth.
7. **TPM unlock phasing:** Phase 1 binds PCR 7 (no Secure Boot); Phase 2 binds
   PCR 0+2+7 with Limine Secure Boot. Never bind PCR 9 (kernel image) or PCR 8
   (store paths) — they break unattended auto-unlock. Always keep the passphrase
   keyslot as fallback.
8. **flake-parts + the dendritic pattern.** `modules/default.nix` explicitly lists
   every file as a flake-parts module; aspects expose `aspects.nixos.<aspect>`
   (and `aspects.homeManager.<aspect>`). Hosts assemble by toggling aspects
   (`with config.aspects.nixos; [ … ]`) in the host assembler module, not by
   sibling `imports` of aspect files.    The assembler (`modules/parts/soyo.nix`) is also a flake-parts module;
   `hosts/soyo/` holds hardware/data only.
9. **Reproducible + recoverable.** Everything declarative. Root is impermanent:
   wiped to a blank Btrfs snapshot (`root`/`root-blank`) in systemd initrd each
   boot, durable state only under `/persist` via the `preservation` module; the
   persisted-path inventory is part of the design. Hardware is declarative via
   `nixos-facter` (`hosts/soyo/facter.json`), not `nixos-generate-config`. Do not
   break TPM auto-unlock or the break-glass paths (local console, LAN initrd SSH,
   direct-link rescue). The agenix host key is read from `/persist` before
   decryption (`age.identityPaths`); `/persist` is `neededForBoot`.
10. **Backups via `restic`** (`services.restic.backups` — the first-class module;
    not rustic/kopia) plus local `btrbk` snapshots. Day-2 remote deploy is native
    `nixos-rebuild --target-host` (local build, remote activation); `deploy-rs` is
    deferred to M4.

## Anti-goals (keep off Soyo)

- local LLM inference (no usable GPU, fixed 16 GB) — API-based agents are fine
- ZFS, NetworkManager on the server
- WAN-inbound services — reach in via Tailscale
- CPU-bursty workloads (game servers, CI runners, heavy DBs)

## Adding a service

1. Prefer a native NixOS module (e.g. `services.jellyfin`); a container only
   where no module exists.
2. Own aspect module under `modules/nixos/<name>.nix` exposing
   `aspects.nixos.<name>`, toggled on per host in the assembler.
   Use the `lanAppliance.services.<name>` option namespace for host-specific data.
3. Resource-isolate it (invariant 2) — every guest service gets `MemoryMax`,
   `CPUQuota`, and a lowered `Nice`.
4. If the service needs a LAN hostname, add it to `hosts/soyo/reservations.nix`
   (the single source of truth drives both Blocky forward-A and dnsmasq PTR).
   Put a reverse proxy (Caddy, internal TLS) in front once there is more than
   one web service.
5. Back up its state as class 3 (restic). Bulk data lives on the NAS over NFS.
6. Reassess RAM/CPU headroom and the widened outage blast radius.

## Secrets quick-reference

- All secrets are `agenix-rekey` rekeyFile flow (never plaintext).
- Master-encrypted `.age` files live in `secrets/`; host-specific rekeyed copies
  live under `secrets/rekeyed/<host>/` (auto-generated by `agenix rekey`).
- **Adding a new secret:**
  1. Create the master-encrypted `.age` file with `agenix edit secrets/<name>.age`
     (uses your SSH key from `masterIdentities` in the host assembler).
  2. Register it in `modules/nixos/users.nix` with `rekeyFile = ../../secrets/<name>.age;`
     and optionally set `owner`/`group` for service access.
  3. Run `agenix rekey` to generate per-host copies.
  4. Commit both `secrets/<name>.age` and the updated `secrets/rekeyed/`.
- Password secrets are SHA-512 hashes from `mkpasswd -m sha-512`.
- MAC/IP addresses are *not* secrets — plaintext in `reservations.nix`.

## Adding a host

- `hosts/<name>/` with its own `facter.json`, `boot.nix`, `disko.nix`,
  `networking.nix`; a host assembler in `modules/parts/<name>.nix`.
- Reuse the `base`, `users`, `home.base`, and `backup` aspects and the disko
  pattern. Do **not** toggle on server-only aspects (DNS, DHCP, remote-unlock)
  for a non-server host.
- New agenix host key: generate an SSH host key, save its public key as
  `secrets/<host>.pub`, set `age.rekey.hostPubkey` in the host assembler to
  that path, run `agenix rekey` to generate per-host rekeyed secrets, then
  commit the new pubkey and rekeyed files.

## Learning docs (required output)

- [`docs/secrets.md`](docs/secrets.md) is the canonical introduction to the
  agenix-rekey rekeyFile workflow, written for beginners. Keep it in sync
  with any secrets-related changes.
- Comment modules with the *why* and the idiom, not just the *what*.
- Introduce one concept at a time along the M1–M4 roadmap.
- When a concept first appears, explain it briefly and link a canonical source:
  [nix.dev](https://nix.dev), the [NixOS](https://nixos.org/manual/nixos/stable/)
  and [Nixpkgs](https://nixos.org/manual/nixpkgs/stable/) manuals,
  [Home Manager](https://nix-community.github.io/home-manager/),
  [flake.parts](https://flake.parts),
  [search.nixos.org](https://search.nixos.org/options).
- Readability over cleverness — it is part of the deliverable.

## Commit message convention

Conventional commits: `type(scope): message`. No period.

## Boundary rules (never modify these)

- `flake.lock` — update only via `nix flake update <input>`.
- `secrets/rekeyed/` — auto-generated by `agenix rekey`; edit the master
  `.age` file, rekey, then commit both.
- `hosts/*/facter.json` — generated by `nixos-facter` on the target hardware;
  never edit by hand.

## SSH access

SSH into any machine via Tailscale: `ssh krzysiek@<machine-dns-name>` (e.g. `ssh krzysiek@soyo`, `ssh krzysiek@zbook`).

## Workflow

- Build order follows the design doc's roadmap; M1 + M2 are the production
  cut-line, M3 hardens (Secure Boot), M4 expands (laptop, services).
- Pre-commit hooks auto-install via `nix develop`.
  Hooks: deadnix, statix, typos, treefmt, end-of-file-fixer, check-merge-conflicts,
  actionlint (GitHub Actions), shellcheck (shell scripts), markdownlint (docs),
  ruff (Python).
  Before committing: `nix flake check` and also run `gitleaks` locally
  (`nix run nixpkgs#gitleaks -- detect --source . --no-git --verbose --config .gitleaks.toml`).
- Everyday deploy: `./scripts/deploy-soyo.sh` (Soyo) or `./scripts/deploy-zbook.sh` (zbook; or `nixos-rebuild switch --flake .#zbook --target-host krzysiek@zbook --sudo`).
- After deploy or after changes that touch boot, unlock, networking, or
  services, run the automated healthcheck:

  ```bash
  nix run .#healthcheck [hostname] [ip]
  ```

  This checks DNS, services, metrics, timers, secrets, Secure Boot, and more
  over SSH. Expect all \[PASS\]; investigate any \[FAIL\].
- The following **can only be verified manually** (reboot, physical access, or
  destructive action):
  - TPM auto-unlock (reboot, should unlock without passphrase)
  - Break-glass passphrase unlock (wipe TPM slot, reboot with passphrase)
  - LAN initrd SSH unlock (reboot, SSH port 2222)
  - Direct-link rescue unlock (physical connection, static IP)
  - DHCP client receives correct DNS/search domain
  - Forced unit failure sends ntfy notification
  - restic restore drill
  - Tampered boot fails checksum verification (M3)
  - TPM re-enrollment restores auto-unlock after PCR change
- Keep host directories thin; push reusable logic into modules.

## Zbook known issues

- **First boot: nouveau instead of NVIDIA.** The flake sets `services.xserver.videoDrivers = [ "nvidia" ]`
  which makes `hardware.nvidia.enabled = true`, but this requires a reboot
  (nouveau claims the GPU first; kernel modules can't hot-swap). Run
  `nixos-rebuild switch --flake .#zbook` then `sudo reboot` after first install.
- **Suspend: USB-C dock immediate wake.** Udev rules in `modules/nixos/laptop.nix`
  disable ACPI wake for USB/Thunderbolt controllers. If wake still happens,
  reboot to ensure udev rules fire at device-probe time.
