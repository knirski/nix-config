# AGENTS.md — guidelines and guardrails

A multi-host NixOS/nix-darwin/standalone-HM flake.

## Hosts

| Host | Role | System | Assembler | Data dir | Status |
| ---- | ---- | ------ | --------- | -------- | ------ |
| **soyo** (Intel N150) | LAN DNS + DHCP appliance, 16 GB | NixOS `release-26.05` | `modules/parts/soyo.nix` | `hosts/soyo/` | M1–M3 complete; M4 appliance items deferred |
| **zbook** (HP ZBook Studio 16" G10) | Workstation/gaming laptop, 32 GB, NVIDIA RTX 4000 Ada | NixOS unstable | `modules/parts/zbook.nix` | `hosts/zbook/` | M4 complete |
| **macbook** (Apple Silicon) | Professional workstation laptop | nix-darwin unstable | `modules/parts/macbook.nix` | `hosts/macbook/` | CI only; hardware deploy pending |
| **ubuntu** (Ubuntu 24.04 LTS) | Professional work laptop | Standalone HM unstable | `modules/parts/ubuntu.nix` | *(data in assembler)* | CI only; hardware deploy pending |

See [`docs/workstation-setup.md`](docs/workstation-setup.md) for macbook/ubuntu deploy status.
See [`docs/superpowers/specs/soyo-dns-dhcp-appliance.md`](docs/superpowers/specs/soyo-dns-dhcp-appliance.md) for the canonical design doc.

## Aspect namespaces

| Namespace | Source dir |
| --------- | ---------- |
| `aspects.nixos.*` | `modules/nixos/*.nix` |
| `aspects.darwin.*` | `modules/darwin/*.nix` |
| `aspects.homeManager.*` | `modules/home/*.nix` |

Host assemblers (in `modules/parts/`) toggle aspects by name via `with config.aspects.nixos; [ … ]`. HM aspects are shared across all host types.

## Hard invariants (never violate without a design-doc decision)

1. **DNS and DHCP are the only critical roles.** Never let another service compromise them.
2. **Guest services are resource-isolated** — every guest gets `MemoryMax`, `CPUQuota`, lowered `Nice`/`IOWeight`.
3. **`base.nix` aspects stay role-neutral** — no network backend, swap policy, or GUI assumptions.
4. **Kernel follows `linuxPackages_latest`** with in-tree `dwmac_motorcomm` NIC driver.
5. **Secrets via agenix-rekey rekeyFile flow** — see [docs/secrets.md](docs/secrets.md) and the secrets section below. Never commit plaintext secrets.
6. **DNS split:** Blocky owns forward A records; dnsmasq owns reverse/PTR (lease-aware). Static hosts from [`hosts/soyo/reservations.nix`](hosts/soyo/reservations.nix).
7. **TPM unlock phasing:** PCR 7 first (no Secure Boot), then PCR 0+2+7 with Limine Secure Boot. Never bind PCR 8 or 9. Always keep passphrase fallback.
8. **flake-parts + dendritic pattern.** `import-tree` discovers modules; aspects opt in via host assembler, not sibling `imports`. Reusable helpers under `lib/`. Host assemblers are also flake-parts modules.
9. **Impermanent root** — wiped to a blank Btrfs snapshot each boot; durable state under `/persist` via `preservation`. Hardware via `nixos-facter`. Agenix host key at `/persist/etc/ssh/`.
10. **Backups via `restic`** (`services.restic.backups` — not rustic/kopia) + `btrbk` snapshots. Deploy with `deploy .#hostname`, `nixos-rebuild --target-host`, or `just deploy`.

## Anti-goals (keep off Soyo)

- local LLM inference (no usable GPU, fixed 16 GB)
- ZFS, NetworkManager on the server
- WAN-inbound services — reach in via Tailscale
- CPU-bursty workloads (game servers, CI runners, heavy DBs)

## Adding a service

1. Prefer a native NixOS module; container only where none exists.
2. Create `modules/nixos/<name>.nix` exposing `aspects.nixos.<name>`. Use `lanAppliance.services.<name>` options for host-specific data.
3. Resource-isolate it (invariant 2).
4. If it needs a LAN hostname, add it to `hosts/soyo/reservations.nix`.
5. Back up its state via restic. Bulk data on NAS over NFS.
6. Reassess RAM/CPU headroom and outage blast radius.
7. **Stage new files before evaluation.** `import-tree` scans the filesystem — newly created `.nix` files under `modules/` won't be discovered until `git add` stages them. Run `git add modules/nixos/<name>.nix` before `nix flake check` or `just deploy`.

### General runtimes vs role aspects

Don't bundle role-neutral runtimes (Node.js, Python, language servers) into role aspects like `desktop` or `server`. A runtime is a general-purpose capability — it may serve backends on soyo *and* developer tooling on zbook. Make it a standalone opt-in aspect (`modules/nixos/<name>.nix`) so each host assembler toggles it independently.

Existing examples:
- `aspects.nixos.nodejs` (`modules/nixos/nodejs.nix`) — Node.js, bun, pnpm, yarn. Enabled on zbook; eligible for soyo if a backend needs it.

## Secrets

- All secrets are `agenix-rekey` rekeyFile flow (never plaintext).
- Master-encrypted `.age` files in `secrets/`; host-specific rekeyed copies in `secrets/rekeyed/<host>/` (auto-generated).
- The master key (`~/.ssh/agenix_master`, symlinked as `/etc/agenix-rekey/master-identity`) is separate from the SSH login key (`krzysiek-authorized-key.pub`). Only master key decrypts `.age` files; only login key goes on hosts.
- **Adding a secret:**
  1. `agenix edit secrets/<name>.age`
  2. Register the `rekeyFile`:
     - **User/password/ntfy secrets** → `modules/nixos/users.nix` (`rekeyFile = ../../secrets/<name>.age;`)
     - **Service/host-specific secrets** (restic passwords, Tailscale auth keys, dev tokens) → the host assembler `modules/parts/<host>.nix` inside its `age.secrets` block
     - Optionally set `owner`/`group`/`mode` for service access
  3. `agenix rekey` → generates per-host copies
  4. Commit `secrets/<name>.age` and the updated `secrets/rekeyed/`
- Password secrets are SHA-512 hashes from `mkpasswd -m sha-512`.
- MAC/IP addresses are *not* secrets — plaintext in `reservations.nix`.

## Adding a host

- `hosts/<name>/` gets `facter.json`, `boot.nix`, `disko.nix`, `networking.nix`; assembler at `modules/parts/<name>.nix`.
- Reuse `base`, `users`, `home.base`, `backup`. Don't toggle server-only aspects (DNS, DHCP, remote-unlock) on non-server hosts.
- New agenix host key: generate SSH host key, save public key as `secrets/<host>.pub`, set `age.rekey.hostPubkey` in assembler, `agenix rekey`, commit.
- **Darwin hosts:** `inputs.nix-darwin.lib.darwinSystem` + `config.aspects.darwin.*`. No disko/boot/persistence. Data in `hosts/<name>/`.
- **Standalone HM hosts:** `inputs.home-manager.lib.homeManagerConfiguration`. Only HM aspects. No `hosts/<name>/` dir — data in assembler. Activate with `home-manager switch --flake .#<host>`.

## Workflow

- **Check your context first.** Before running a command that targets a host, check the local hostname with `hostname`. If it matches the target, run commands locally instead of via SSH. This avoids unnecessary SSH loopback and ensures local hardware detection (GPUs, displays, sensors) works correctly.
- Run [`just`](justfile) to list all recipes (self-documenting). Key ones: `deploy <host>` (everyday deploy), `check` (full `nix flake check`), `lint` (pre-commit + gitleaks), `healthcheck`, `rekey`, `topology`.
- Pre-commit hooks auto-install via `nix develop`. Run `just lint` before committing.
- After deploy or after touching boot/unlock/networking/services, run `just healthcheck <host>`. Expect all \[PASS\].
- The following require **manual verification** (reboot / physical access / destructive action):
  TPM auto-unlock, break-glass passphrase unlock, LAN initrd SSH unlock, direct-link rescue unlock, DHCP client DNS, forced unit failure → ntfy, restic restore drill, tampered boot rejection, TPM re-enrollment.
- Keep host directories thin; push reusable logic into modules.

### External Linux research

- For Linux/NixOS troubleshooting, consult the [ArchWiki](https://wiki.archlinux.org/) and [Arch Linux Forums](https://bbs.archlinux.org/) alongside NixOS, kernel, and upstream project documentation.
- Use the ArchWiki for practical Linux behavior, configuration patterns, and troubleshooting procedures. Link the specific article when an external workaround informs a change, and account for Arch-specific paths, package names, and service defaults.
- Search the Arch Linux Forums for hardware-, kernel-, driver-, and version-specific field reports. Treat forum posts as hypotheses and reproduction leads, not authoritative conclusions; corroborate them with local logs and primary upstream documentation or issues before adopting them.
- Record the relevant hardware, kernel, driver, and software versions when applying advice. Separate observed facts from inferences, and translate imperative Arch commands into declarative NixOS configuration rather than copying them blindly.

## Boundary rules (never modify these)

- `flake.lock` — update only via `nix flake update <input>`.
- `secrets/rekeyed/` — auto-generated by `agenix rekey`.
- `hosts/*/facter.json` — generated by `nixos-facter`; never edit by hand.

## Learning docs (required output)

- [`docs/secrets.md`](docs/secrets.md) is the canonical agenix-rekey walkthrough for beginners. Keep in sync with secrets changes.
- Comment modules with the *why* and the idiom, not just the *what*.
- Introduce one concept at a time along the M1–M4 roadmap.
- When a concept first appears, explain it briefly and link a canonical source: [nix.dev](https://nix.dev), the [NixOS](https://nixos.org/manual/nixos/stable/) and [Nixpkgs](https://nixos.org/manual/nixpkgs/stable/) manuals, [Home Manager](https://nix-community.github.io/home-manager/), [flake.parts](https://flake.parts), [search.nixos.org](https://search.nixos.org/options).
- Readability over cleverness — it is part of the deliverable.

## Zbook known issues

- **Disabling lid-close suspend.** `disable-lid` in `modules/home/desktop.nix` wraps `systemd-inhibit --what=handle-lid-switch sleep infinity`. Cancel with Ctrl+C.
- **First boot: nouveau instead of NVIDIA.** Reboot after first `nixos-rebuild switch`.
- **Suspend: no deep S3.** HP firmware can't route S3 wake events; s2idle used instead. If immediate wake after suspend (machine re-wakes ~3 s after suspend entry while docked), the `0bda:8153:j` usbcore quirk in `modules/nixos/laptop.nix` disables remote wake on the dock's RTL8153 Ethernet at the USB-core level — a udev rule alone isn't enough, the r8152 driver re-enables wakeup on bind. Needs reboot.
- **Logitech receiver stutter.** Fixed by `usbcore.quirks` in `modules/nixos/laptop.nix` (`boot.kernelParams`). Requires reboot.
- **NVIDIA GSP firmware crash on s2idle resume.** Fixed by `NVreg_EnableGpuFirmware=0` in `modules/nixos/nvidia.nix`. Requires cold reboot.
- **DMS auto-suspend while media playing.** Fixed by `media-sleep-inhibit` systemd user service in `modules/home/sway.nix` (polls MPRIS via `playerctl` every 15s).
- **NetworkManager "connected" but no internet after s2idle.** Fixed by `powerManagement.resumeCommands` in `modules/nixos/laptop.nix` (restarts NetworkManager on resume).
- **NVMe hang + btrfs read-only after s2idle resume.** The XPG S70 Blade can
  fail to wake from a low-power state, wedging the PCIe link: the disk stops
  answering, btrfs remounts read-only after command timeouts, and only a cold
  reboot recovers. The journal ends abruptly with no kernel messages —
  they're stuck in journald's buffer on the same dead disk. Recurring: check
  SMART `unsafe shutdowns` (a wedged controller can't even record the event)
  and the daily "uncleanly shut down" journal lines for the pattern. Mitigated by
  `nvme_core.default_ps_max_latency_us=0`
  ([kernel parameter docs](https://docs.kernel.org/admin-guide/kernel-parameters.html))
  plus `pcie_aspm=off` (APST alone did not stop the wedge — the failing
  power state is the link itself) and the `disable-nvme-apst` service, which
  re-asserts the disable per controller (PM QoS sysfs node) on every resume,
  in `modules/nixos/laptop.nix`. Requires a reboot.
- **Recurrent wedge + VPD access failure (2026-08-11).** All three mitigations
  above were active (`/proc/cmdline` confirmed `nvme_core.default_ps_max_latency_us=0`
  and `pcie_aspm=off`, `disable-nvme-apst.service` enabled and ran on boot), yet
  the wedge recurred: boot -1 ended abruptly at 02:22:13 with no kernel
  messages, and boot 0 logged `system.journal corrupted or uncleanly shut down`
  at 03:03:12 — a ~41-min dark gap resolved by a forced cold shutdown. The
  leading symptom this time was `nvme 0000:03:00.0: VPD access failed. This is
  likely a firmware bug on this device. Contact the card vendor for a firmware
  update` at 02:12:05, ~3 s after a resume — a PCIe config-space (VPD) read
  failure that predates any filesystem symptom. The S70 Blade runs an InnoGrit
  controller (subsystem NQN `nqn.2016-11.com.innogrit:2N11292JQEJC`); the
  kernel's own recommendation is a vendor firmware update, and the in-kernel
  power-state mitigations are already maxed out (`pcie_aspm=off`, APST
  disabled) — no further software lever remains. Firmware at time of wedge:
  `3.2.F.74` per `nvme id-ctrl`. A firmware check via AData SSD Toolbox
  (booted from a live Windows 10 USB, 2026-08-12) reports **no update
  available** — `3.2.F.74` is current. All mitigations therefore stay in
  force permanently; treat s2idle on this drive as unreliable: prefer
  `systemctl hibernate` or a full shutdown over suspend, and treat
  `VPD access failed` in the journal as an early-warning signal that the next
  wedge is imminent.
