# Soyo DNS/DHCP Template Design

## Goal

An idiomatic multi-host Nix flake whose first host is a Soyo M4 Pro acting as a DNS and DHCP appliance, using declarative encrypted storage, agenix secrets, and a systemd-based boot. Existing real-world data (DHCP reservations, local DNS records) is migrated from the current router/dnsmasq setup. The disk unlocks automatically via the TPM on a trusted boot, so a normal power loss recovers unattended; manual and remote unlock are break-glass fallbacks for when TPM unlock cannot proceed.

## Scope

Covers:

- repository structure and module boundaries
- Soyo host configuration
- declarative disk partitioning and filesystem layout
- user and secret management with agenix
- user environment with Home Manager
- data classification and backup to the LAN Synology DS423+
- DNS and DHCP service design
- naming policy for `IP`, `soyo`, and `soyo.home.arpa`
- IPv4/IPv6 addressing decision
- first-install and USB-boot provisioning
- `nixos-unstable` upgrade workflow
- power-loss and unlock recovery
- maintenance defaults
- learning-oriented documentation (with canonical source links) produced by the implementation

Does not cover:

- hosted application services such as media (deferred but anticipated; see Future Services on Soyo)
- desktop/gaming-laptop implementation, or GUI Home Manager modules (server uses a headless HM profile)
- unattended updates
- automated secret rotation beyond the basic agenix model

## Non-Goals

- making Soyo the internet gateway, firewall, or Wi-Fi controller
- ZFS or a heavier filesystem
- relying on router DHCP as the normal recovery path
- building a generic framework for every future machine class before the first host exists

## Design Principles

1. Prefer existing NixOS ecosystem tools over custom scripts.
2. Use systemd-native mechanisms where current NixOS provides them.
3. Keep host directories thin; move reusable logic into focused modules.
4. Make install, rebuild, upgrade, and recovery reproducible from repo state plus documented operator inputs.
5. Treat power-loss recovery as first-class.
6. Keep Soyo server-focused while leaving clean boundaries for future laptop hosts.

## Learning Goals

This repo doubles as a way to learn idiomatic Nix and NixOS from basics. This is a requirement on the implementation's output, not on this design doc — the code and the docs it ships must teach:

- comment modules with the *why* — what each option does and the idiom behind it — not just the *what*
- introduce one concept at a time along the M1–M4 roadmap (flake-parts, the module system and options, derivations, disko, agenix, Home Manager) rather than all at once
- when a concept first appears, explain it briefly in the docs and link a canonical source: [nix.dev](https://nix.dev), the [NixOS manual](https://nixos.org/manual/nixos/stable/), the [Nixpkgs manual](https://nixos.org/manual/nixpkgs/stable/), [Home Manager manual](https://nix-community.github.io/home-manager/), [`flake.parts`](https://flake.parts), and the relevant [search.nixos.org](https://search.nixos.org/options) option
- prefer clear idiomatic patterns over clever ones; readability is part of the deliverable

This repo deliberately leans into radical-modern Nix as a learning vehicle: a dendritic flake (every file an aspect module, auto-imported), impermanence from day one, and declarative hardware via `nixos-facter`. The dendritic pattern and impermanence trade some flat-file legibility for higher learning value; the docs compensate by explaining the aspect→host wiring and the persisted-path inventory explicitly. Home Manager is the one deliberately mainstream idiom in the mix.

**Beginner-friendly documentation is a first-class deliverable, not a by-product.** Precisely because the chosen stack (dendritic flake, `import-tree`, impermanence with blank-snapshot rollback, `nixos-facter`, agenix, TPM/Secure Boot) sits well above a beginner's starting point, the repo must ship a guided learning path that a Nix novice can actually follow:

- a **design-journey narrative** that derives the design from basics: start from the simplest thing that could work and present the important transient steps that led here, showing what was tried, what was rejected, and *why* at each fork (flake → flake-parts → dendritic; mutable root → impermanence → blank-snapshot rollback + `preservation`; `nixos-generate-config` → `nixos-facter`; rustic/kopia → restic; deploy-rs → native `nixos-rebuild`; lanzaboote → Limine; AdGuard → Blocky + dnsmasq). The reader should see the design as a sequence of motivated choices, not a finished monolith; each step links to the matching Appendix entry
- a single entry-point document (e.g. `docs/learning/README.md`) with an explicit reading order, from "what is a flake" through to the appliance's advanced pieces, mapped onto the M1–M4 roadmap so concepts arrive one at a time
- a short glossary of the non-obvious terms this repo leans on (flake-parts, aspect module, dendritic, `import-tree`, impermanence, subvolume, PCR, keyslot, DoH, reservation)
- per-concept explainer notes: each new concept gets a few sentences of plain-language "what it is / why we use it here" plus a link to the canonical source, written for someone who has not seen it before
- the dendritic indirection in particular must be documented so a reader can answer "given `hosts/soyo`, what is actually turned on and where does it come from?" without already knowing the pattern
- worked, copy-pasteable command sequences in the operator runbooks (install, update, recovery), not just prose

The success test: a competent engineer new to Nix can read the learning docs in order and understand both *what* the appliance does and *why each modern choice was made*, without prior NixOS exposure.

## Key Decisions

Load-bearing choices at a glance; rationale and rejected alternatives are in the body and appendix.

| Area | Decision |
|---|---|
| Flake organization | `flake-parts` + dendritic: `import-tree` auto-imports aspect modules into `flake.modules.nixos.*`; hosts assemble by toggling aspects |
| Filesystem | LUKS2 + Btrfs (zstd, subvolumes); impermanent root from day one; durable state under `/persist`, `/nix`, snapshots; no ZFS |
| Impermanence | `preservation` for the persisted-path inventory; root rolled back to a blank Btrfs snapshot in systemd initrd each boot |
| Hardware facts | `nixos-facter` (committed `facter.json`), not `nixos-generate-config` |
| Swap | `zramSwap`, no on-disk swap |
| Kernel | `linuxPackages_latest`; in-tree `dwmac_motorcomm` NIC driver — no pin, no out-of-tree module |
| DNS | Blocky (forwarding/caching + ad-block) on port 53 |
| DNS upstream | DoH to DNS4EU NoAds (general filtering) + Quad9 fallback; one local Polish blocklist; static-IP `bootstrapDns` |
| DHCP + local PTR | dnsmasq, reverse zone conditionally forwarded from Blocky |
| Secrets | agenix, hashed passwords, offline key/LUKS-header backup |
| User environment | Home Manager as a NixOS module, headless profile |
| Network backend | `systemd-networkd` (server-scoped, not in base) |
| Bootloader | Limine (in-tree nixpkgs module, CI-tested, no extra flake input) |
| Boot / unlock | TPM2 auto-unlock (primary), phased: PCR-7 convenience first, then Limine Secure Boot with PCR 0+2+7 (Microsoft keys kept); break-glass via local console, LAN initrd SSH, or direct-link rescue (laptop + Ethernet) |
| Backups | restic to Synology DS423+ (first-class `services.restic.backups`), local Btrfs snapshots, GitHub for config |
| Health checking | self-heal + ntfy OnFailure + Synology Uptime Kuma probe |
| Redundancy | single disk, no RAID; verified backups are the resilience story |
| Updates | manual but easy `nixos-unstable`; unattended out of scope |

## Chosen Tooling

- `flake-parts` — modular flake outputs and per-class module composition
- `import-tree` — dendritic auto-import: every file under the module tree becomes a flake-parts module contributing to `flake.modules.nixos.*` / `flake.modules.homeManager.*`
- `nixos-facter` — declarative hardware detection; a committed `facter.json` replaces the generated `hardware-configuration.nix`
- `disko` — declarative GPT, LUKS2, Btrfs layout
- `preservation` — explicit persisted-path inventory on top of a root rolled back to a blank snapshot each boot (a newer, more principled alternative to `impermanence`). Note: neither is in nixpkgs; `impermanence` is the more battle-tested, example-everywhere choice. The maturity argument (the same one that picks `restic` over `rustic`) was considered and **consciously overridden** here by the radical-modern learning goal — `preservation` is the deliberate teaching choice, with fewer examples accepted as part of the learning cost
- `agenix` — encrypted secrets, including password hashes
- `agenix-rekey` — optional operator-side rekey helper kept as the migration path once multi-host secret churn justifies moving beyond plain `agenix`
- Home Manager — declarative per-user environment and dotfiles
- `restic` — encrypted, deduplicated off-host backups to the Synology DS423+ via the first-class `services.restic.backups` NixOS module
- `btrbk` — scheduled local Btrfs snapshots
- `nixos-anywhere` — alternative remote provisioning over SSH
- `deploy-rs` — multi-host remote deployment (deploy checks, magic-rollback); **deferred to M4** — M1/M2 use the first-class native `nixos-rebuild --target-host`, which needs no extra input for a single host
- `treefmt-nix` — repo-wide formatting
- `deadnix` — unused-binding analysis
- `systemd-networkd` — runtime network manager
- systemd initrd networking + SSH — break-glass remote unlock
- Limine — UEFI boot and Secure Boot; in-tree nixpkgs module, no external flake input
- `systemd-cryptenroll` — TPM2-backed LUKS auto-unlock, passphrase keyslot kept as fallback
- `sbctl` — Secure Boot key management for Limine Phase 2
- Blocky — forwarding/caching DNS with local records, chosen for ad/tracker blocking
- dnsmasq — DHCP and lease-aware local reverse lookup
- Prometheus `node_exporter` — lightweight host metrics
- Prometheus dnsmasq exporter — DHCP and dnsmasq metrics

## Filesystem Choice

`LUKS2` + `Btrfs` (zstd, subvolumes) inside the encrypted container, with an impermanent root achieved by **rolling the root subvolume back to a blank snapshot on every boot** rather than a tmpfs root.

- root is a real Btrfs subvolume, but a `root-blank` readonly snapshot is taken once at install; a systemd-initrd service deletes the live `root` and restores it from `root-blank` before mount, so undeclared state disappears on reboot
- this is the "erase your darlings" idiom on Btrfs; preferred over tmpfs root because it has no RAM ceiling on root contents and keeps a uniform Btrfs layout that `disko` models cleanly
- durable state is anchored in subvolumes under `/persist` and reintroduced into normal runtime paths via the `preservation` module
- snapshots and subvolumes give point-in-time recovery without ZFS-level operational weight
- Btrfs is in-tree on any kernel and needs no DKMS; ZFS is out-of-tree, and the host already carries one out-of-tree module (the NIC) — a second for the filesystem is undesirable

## Repository Structure

A multi-host flake from day one.

### Flake Organization

Built on `flake-parts` with the **dendritic pattern**, adopted deliberately as a radical-modern learning target:

- `flake-parts` gives modular outputs (formatter, checks, dev shell, Home Manager) instead of one monolithic `flake.nix`
- `import-tree` auto-imports every `.nix` file under the module tree as a flake-parts module; each file is one *aspect* and contributes to a shared namespace (`flake.modules.nixos.<aspect>`, `flake.modules.homeManager.<aspect>`)
- a host is assembled by listing the aspects it turns on, not by `imports` of file paths; shared behavior lives in the aspect modules
- legibility — which matters most during recovery — is preserved by documentation: the host file enumerates its aspects, and the docs explain the aspect→host wiring rather than relying on flat imports

The dendritic pattern's earlier rejection (see appendix) is explicitly reversed: the learning goal now outweighs the legibility cost, and the docs mitigate that cost.

### Top Level

- `flake.nix` — thin, on `flake-parts` with `import-tree`; declares inputs (`flake-parts`, `import-tree`, `nixos-facter-modules`, `home-manager`, `disko`, `preservation`, `agenix`, `agenix-rekey`); composes per-host `nixosConfigurations.<hostname>` by toggling aspect modules, with Home Manager as a NixOS module; exposes formatter, checks, dev shell, and any update/deploy helper apps (`deploy-rs` added at M4 for multi-host)
- `hosts/` — one directory per machine
- `modules/` — reusable NixOS modules by responsibility
- `secrets/` — agenix secret files and recipient mapping
- `docs/` — operator install, maintenance, recovery docs
- `scripts/` — thin update/deploy wrappers

### Proposed Module Layout

`import-tree ./modules` auto-imports every file under `modules/` as a flake-parts module. Two kinds live there:

- *flake-parts modules* under `modules/parts/`, which build flake outputs:
  - `modules/parts/perSystem.nix` — `systems`, `treefmt`, formatter, `checks`, dev shell
  - `modules/parts/soyo.nix` — **the host assembler**: builds `flake.nixosConfigurations.soyo` by toggling aspects (`with config.flake.modules.nixos; [ … ]`), importing the input modules (disko, preservation, agenix, home-manager, facter), and importing the host-data files from `hosts/soyo/`. Home Manager is wired here (it needs `config.flake.modules.homeManager.base`).
- *aspect modules*, each defining `flake.modules.nixos.<aspect>` (or `flake.modules.homeManager.<aspect>`) that a host opts into. Paths are organisational; the namespace, not the directory, is what hosts reference:
  - `modules/nixos/base.nix` — common defaults shared across hosts
  - `modules/nixos/server.nix` — server-only defaults
  - `modules/nixos/users.nix` — user policy and the agenix secret inventory
  - `modules/nixos/persistence.nix` — the `preservation` mechanism, the blank-snapshot rollback service, agenix identity path, and teaching comments around persisted state
  - `modules/nixos/remote-unlock.nix` — shared initrd unlock building blocks
  - `modules/nixos/blocky.nix` — Blocky DNS aspect (full settings passthrough)
  - `modules/nixos/dhcp.nix` — dnsmasq DHCP aspect
  - `modules/nixos/maintenance.nix` — `nix.gc`, store optimisation, scrub, journald/boot-entry limits, `smartd`, free-space monitoring, ntfy notifications, time sync
  - `modules/nixos/backup.nix` — restic jobs, snapshot scheduling, repo-secret wiring
  - `modules/nixos/observability.nix` — on-box exporters, Grafana dashboards, Loki logs, Tempo traces; all resource-isolated as guest services
  - `modules/home/base.nix` — shared headless Home Manager aspect

### Soyo Host Layout

The assembler is the flake-parts module `modules/parts/soyo.nix` (it must read `config.flake.modules.*`, which a plain `hosts/soyo/default.nix` cannot). `hosts/soyo/` therefore holds **only** machine facts and host-specific data/values that the assembler imports; reusable behavior lives in the aspect modules above.

- `hosts/soyo/facter.json` — committed `nixos-facter` hardware report (replaces `hardware-configuration.nix`)
- `hosts/soyo/boot.nix` — kernel, firmware, systemd initrd, TPM2 auto-unlock, Limine (Secure Boot in Phase 2), zram
- `hosts/soyo/disko.nix` — GPT, EFI, LUKS2 (with TPM2 crypttab option), Btrfs subvolumes incl. `root` (+ the `root-blank` snapshot taken at install)
- `hosts/soyo/persistence.nix` — the persisted-path inventory for system and user state (sets `preservation.preserveAt."/persist"`)
- `hosts/soyo/networking.nix` — static LAN addressing and firewall
- `hosts/soyo/initrd-unlock.nix` — initrd SSH and network: the static LAN address plus a second dedicated direct-link rescue address, for break-glass unlock
- `hosts/soyo/reservations.nix` — single source of truth: `{ name; mac; ip; }` list, imported by both `dhcp.nix` and `dns.nix`; plaintext (MAC/IP are not secrets)
- `hosts/soyo/dns.nix` — Soyo Blocky policy and forward A records from `reservations.nix` (reverse/PTR is dnsmasq's job)
- `hosts/soyo/dhcp.nix` — DHCP ranges, router options, and `dhcp-host` reservations from `reservations.nix`
- `hosts/soyo/users.nix` — host-specific user assembly (root + krzysiek, password secrets)
- `hosts/soyo/backup.nix` — Soyo backup paths, schedule, Synology target (restic)
- `hosts/soyo/observability.nix` — Soyo exporter settings and LAN-facing metrics bindings

Home Manager additions are wired in the assembler (which can reach `config.flake.modules.homeManager.base`); there is no `hosts/soyo/home.nix`. This separates machine facts from reusable service behavior, so a future laptop reuses the base and user aspects without inheriting server networking or unlock logic.

## Host Role

Soyo is a DNS and DHCP appliance on an existing home LAN.

The router keeps providing WAN uplink, NAT, Wi-Fi, switching, and the client default gateway. Soyo provides DHCP leases, DNS, its own local naming, and local reverse lookups for DHCP clients. Soyo is not the default gateway.

Soyo may later host lightweight home services (see Future Services on Soyo), but DNS and DHCP remain its only critical roles, and the Synology DS423+ stays the primary storage tier.

### Service Availability and Single Point of Failure

Soyo is the LAN's only DNS and DHCP service, so while it is fully down the LAN loses both. The design accepts this rather than weakening filtering. TPM2 auto-unlock shrinks the risk to genuine outages: a reboot, rebuild, or power loss recovers unattended in about a minute, so the real exposure is hardware failure or a botched update, not routine restarts.

Mitigations:

- TPM2 auto-unlock keeps restarts and power-loss recovery fast and unattended
- DHCP lease times are long enough that clients keep addressing through brief downtime
- the documented router-DHCP re-enable fallback (see Router Preparation) covers a prolonged outage such as dead hardware
- no secondary resolver is pushed in DHCP options — a fallback resolver would let clients bypass Blocky filtering

This keeps filtering always enforced and makes extended downtime an operator action (re-enable router DHCP), not a silent bypass.

## Boot and Kernel Model

- UEFI boot
- Limine bootloader throughout, Secure Boot enabled in Phase 2 (see PCR Binding and Secure Boot)
- systemd initrd, required for TPM2 unlock
- `linuxPackages_latest` with the in-tree `dwmac_motorcomm` driver — no pin needed (see below)

### Kernel and NIC Driver

The onboard Ethernet is the Motorcomm `YT6801` Gigabit controller (`1f0a:6801`). After this hardware shipped without a mainline driver, the `dwmac_motorcomm` in-tree driver landed in Linux 6.13 and is present in `linuxPackages_latest` (7.1.1+ at the time of writing). The NIC is confirmed working on the unit via this driver. (The nixpkgs 26.05 default kernel config does not enable the module, so we explicitly use `linuxPackages_latest`.)

Decision: use `linuxPackages_latest` with the in-tree `dwmac_motorcomm` driver — no kernel pin, no out-of-tree module. This avoids the maintenance burden of a compat-limited vendor module. If a future kernel regression breaks the NIC, fall back to the pinned-out-of-tree strategy described in the Alternatives appendix.

## Disk Layout

`disko`: one GPT disk, one EFI System Partition, one LUKS2 partition, one Btrfs filesystem inside it. Root is a Btrfs subvolume that is wiped to a blank state every boot, not a tmpfs.

Subvolumes and mount intent:

- `root` — `/`, the live root subvolume; rolled back to `root-blank` on every boot
- `root-blank` — a readonly snapshot of an empty `root`, taken once at install; the initrd restores `root` from it before mount
- `nix` — `/nix`
- `persist` — the durable anchor for files and directories reintroduced into the wiped root, including the dnsmasq lease database so leases and reservation state survive reboots/rebuilds (no duplicate-IP handouts)
- `snapshots` — local snapshot target

The rollback runs as a `boot.initrd.systemd.services` unit, ordered `After` the LUKS device opens and `Before` `sysroot.mount`. Gotcha confirmed across reference implementations (Misterio77/nix-config `ephemeral-btrfs.nix`, Electrostasy/dots `restore-root.nix`, the misterio entry in `nix-community/nur-combined`): the live `root` cannot be deleted with a plain `btrfs subvolume delete` once **nested subvolumes** exist under it (systemd creates some, e.g. under `/var/lib`; services with `DynamicUser`/`ProtectSystem` create more). The rollback must enumerate and delete nested subvolumes first (recursive delete / a delete loop) before snapshotting `root` from `root-blank`, or the wipe fails and the unit blocks boot. Persistent state is then reintroduced into normal Linux paths from `persist` via an explicit inventory. The baseline intentionally uses impermanence from the beginning, so state completeness is part of correctness, not a later cleanup exercise.

### Swap

`zramSwap`, no on-disk swap. With 16 GB RAM the box rarely needs swap; zram keeps any swap in the compressed memory path and avoids swap-on-Btrfs and swap-on-LUKS complications, so the disko layout needs no swap device.

## Impermanence Baseline

Impermanence is part of the baseline Soyo design. This repo explicitly optimises for learning value, so root starts ephemeral and the persisted-path inventory becomes a first-class artifact rather than an operational afterthought.

### What It Means Here

The rough shape is:

- the root subvolume is wiped at boot by restoring it from a blank Btrfs snapshot (`root-blank`) in systemd initrd, rather than mounting a tmpfs root
- a dedicated `persist` subvolume remains the durable anchor
- selected state is bind-mounted or otherwise restored from `persist` into standard runtime paths
- declarative config still comes from the flake; only non-derivable state survives across boots

The implementation uses the `preservation` module for the persisted-path wiring (a newer, more principled alternative to `nix-community/impermanence`), but the code and docs must also explain the underlying mechanism: blank-snapshot rollback of root, early durable mounts, then explicit restoration of the state that should survive. The host SSH key that agenix needs is part of that early restoration (see Secrets and Users).

### Minimum Persistent Inventory

At minimum, this baseline needs an explicit persisted-path inventory for:

- DHCP and service state under `/var/lib`, especially the dnsmasq lease database
- persistent logs under `/var/log` if they remain part of the operational model
- `/var/lib/nixos`, so declarative users and groups keep stable numeric IDs across reboots
- machine identity such as `/etc/machine-id`
- SSH host keys and any other long-lived host identity not already handled elsewhere
- real user data under `/home`
- any service databases or application state added later in M4

Deliberately **not** persisted: `/etc/{passwd,group,shadow,gshadow,subuid,subgid}`. With `users.mutableUsers = false` and `hashedPasswordFile` (agenix), NixOS regenerates these declaratively from config at every activation, so persisting them would only risk drift. `/var/lib/nixos` (the UID/GID map) is what must persist for stable IDs.

The important point is that impermanence does **not** remove state management; it makes that inventory stricter and more visible.

### Benefits

Impermanence is attractive here for real reasons:

- it forces an explicit inventory of state that must survive reboot
- it makes accidental local drift less likely, because undeclared writes disappear on reboot
- it sharpens the boundary between declarative system config and runtime data
- it is a strong learning tool for understanding which files NixOS services actually need to keep
- it can make rebuild-and-recover workflows feel cleaner once the persisted set is correct

For a learning repo, that discipline is valuable: missing persistence usually fails loudly instead of remaining hidden as historical machine state.

### Trade-Offs

Using impermanence from the beginning is valuable for learning, but it comes with real cost for the LAN's only DNS/DHCP appliance:

- every critical service must be checked for hidden writes outside the persisted set
- the break-glass and power-loss paths need another full validation pass
- install, recovery, backup, and restore docs all become more complex
- mistakes are more likely to show up as boot-time or first-request failures rather than ordinary configuration drift

That is the core trade-off:

- **benefit** — better state discipline and a clearer picture of what the configuration really covers
- **cost** — a more failure-sensitive bring-up, with more ways to miss a required path and break a critical appliance at boot or after reboot

For this repo, that cost is accepted deliberately in exchange for the higher learning rate.

## Secrets and Users

agenix, not sops-nix.

### Secret Model

- `secrets/secrets.nix` maps secrets to recipients
- encrypted password hashes: `secrets/root-password.age`, `secrets/krzysiek-password.age`
- recipients: the operator key (management machine) and the Soyo host key (after install)

Impermanence ordering caveat: agenix decrypts at boot using the Soyo host SSH key, but under the wiped-root baseline `/etc/ssh` is empty until `preservation` reintroduces it — so relying on the default `/etc/ssh/ssh_host_ed25519_key` path risks agenix running before the key is in place and failing to decrypt the password hashes, leaving the box unusable.

Researched fix (well-attested across `ryantm/agenix` reference docs, `oddlama/nix-config`, `MatthewCroughan/nixcfg`, `Arcanyx-org/NiXium`): point agenix directly at the durable copy instead of depending on the bind-mount ordering —

- `age.identityPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];`
- mark the persist filesystem `neededForBoot = true` so it is mounted before stage-2 activation runs

The persisted-path inventory, `age.identityPaths`, and `neededForBoot` are therefore part of M1 correctness, not an M2 concern.

Baseline phasing matters here:

- M1 uses `agenix-rekey`'s `rekeyFile` flow from day one — every secret is master-encrypted and rekeyed per host. The initial design deferred this to M2/M4 (see [design journey](/docs/learning/design-journey.md)), but `rekeyFile` was chosen upfront to avoid a painful migration later and because `agenix-rekey` is near-instant on already-rekeyed secrets.

### User Model

- `root` — password hash from agenix, for console and break-glass only; direct SSH login disabled (`PermitRootLogin no`)
- `krzysiek` — admin user, password hash from agenix, SSH key auth, `wheel`, escalates via `sudo`

Passwords are hashed-password secrets, never plaintext.

### SSH Policy

Runtime sshd is key-only and LAN-facing: password auth disabled globally, root SSH disabled (admin via `krzysiek` + `sudo`), not exposed on any WAN interface. The root password remains for local console and the break-glass unlock path, where SSH keys are unavailable.

### Backup of Recovery Material

Off-host, offline backup for material that cannot be regenerated from repo state, since Soyo itself may be the failed component:

- the operator age/SSH private key (decrypts and rekeys agenix secrets) — losing it makes every secret unrecoverable; back up independent of Soyo and the management machine
- the LUKS2 header — so a partially damaged disk can still be unlocked
- the host key material agenix needs on the installed system

## User Environment with Home Manager

The admin user's shell and dotfiles are declarative via Home Manager — an explicit learning goal and the canonical way operator tooling is defined.

- runs as a NixOS module inside each `nixosConfiguration`, so one `nixos-rebuild` applies system and user state
- `modules/home/base.nix` holds the headless profile (shell, prompt, git, editor, CLI tools) as `flake.modules.homeManager.base`; the host assembler (`modules/parts/soyo.nix`) wires it in and layers any Soyo additions
- headless only: no desktop, GUI, or theming
- manages config/dotfiles, not real user data (documents, app databases) — that is a backup concern

Because dotfiles are declarative and in GitHub, they need no NAS backup. Real data under the user's home is class 3, must be declared in the persisted-path inventory once introduced, and is then backed up explicitly (see Data and Backup Strategy).

## Networking Model

`systemd-networkd` as the runtime network manager: server-idiomatic, clean with static interfaces, aligned with systemd initrd networking, and avoids mixing NetworkManager into an appliance role.

### Normal LAN Addressing

Soyo uses a static LAN IPv4 outside the DHCP pool — the everyday management address and the LAN unlock address. The initrd also carries a second dedicated static address in a small separate subnet for direct-link rescue (laptop straight into the wired port). The DHCP pool reserves three ranges: infrastructure/static, normal client, and an optional emergency manual range.

### Example Addressing

Editable defaults; the real values live in host-local config, not this design doc:

- router/gateway: `10.0.0.1`
- Soyo LAN IP: `10.0.0.9/24`
- infrastructure/static range: `10.0.0.2`–`10.0.0.49`
- DHCP pool: `10.0.0.50`–`10.0.0.199`
- emergency manual range: `10.0.0.200`–`10.0.0.219`
- direct-link rescue subnet: `192.168.254.0/30` — recovery laptop `192.168.254.1`, Soyo initrd `192.168.254.2`
- search/local domain: `home.arpa`

### IPv6 Decision

IPv4-only for the appliance role: dnsmasq hands out IPv4 leases and Soyo advertises itself as the IPv4 resolver. The router keeps any IPv6 it provides via RA — and clients getting an IPv6 resolver from RA may bypass Soyo's DNS over IPv6, weakening filtering and local naming on those queries. Recommend either disabling the router's IPv6 RDNSS so clients prefer Soyo, or accepting the split as out of scope. Full dual-stack DHCPv6/IPv6 DNS is deferred.

### Firewall

On the LAN interface only, never WAN-facing:

- DNS: TCP+UDP 53
- DHCP: UDP 67
- initrd and runtime SSH

### Time

`timesyncd` (default-on) for correct DNS logs, lease timestamps, and future DNSSEC. NTP servers configured by IP, not hostname — otherwise time sync waits on DNS while DoT upstreams wait on valid time, a boot-ordering deadlock.

## Naming Policy

Reachable by raw IP, `soyo.home.arpa`, and the bare `soyo` where the client supports it. Naming is unicast only via Soyo's own Blocky — no mDNS/Avahi, since running the LAN DNS means a unicast record plus a DHCP search domain covers naming without an extra daemon. `soyo.local` / mDNS / Avahi is intentionally out of scope: the appliance already provides unicast DNS, and recovery paths use the raw IP.

- raw IP — canonical for provisioning and recovery
- `soyo.home.arpa` — canonical internal FQDN, an explicit Blocky A/AAAA record
- `soyo` — bare label, resolved by clients appending the DHCP search domain (`home.arpa`)

Unicast DNS has no native single-label resolution: a bare `soyo` resolves only if the client appends the search domain. So provide the explicit `soyo.home.arpa` record, push the `home.arpa` search domain via DHCP, and document that a client with no search domain must use the FQDN or raw IP.

## DNS Design

Blocky is the client-facing DNS server on port 53 — a forwarding/caching resolver with blocking, not recursive. It answers from cache and local records and forwards the rest.

Responsibilities: upstream forwarding + caching, local host records, ad/tracker filtering, and local naming.

Upstream is DoH (encrypted, private from the ISP) to **DNS4EU NoAds** as primary — it filters general ads/trackers/malware upstream, so we maintain almost nothing — with **Quad9** DoH as a privacy-respecting, malware-filtering fallback. Local blocking is kept to a single auto-refreshing **Polish** blocklist for the niche the upstream misses; it applies to every answer, including failover. This split (general filtering upstream, one local list) is the low-maintenance baseline; avoid accumulating a large fragile third-party collection. As the LAN's only resolver, Blocky sets a static-IP `bootstrapDns` to reach the DoH upstreams and fetch the blocklist at boot before name resolution exists; DoH also needs correct time at startup (NTP by IP, see Time).

### Client DoH/DoT Bypass

Browsers and some OSes resolve over their own encrypted DNS, bypassing Blocky. Soyo is not the gateway, so it cannot block this at the network layer. Partial mitigations within Soyo's control: answer the Firefox canary `use-application-dns.net` as blocked (Firefox then disables its auto-DoH), and blocklist well-known public DoH hostnames. Residual per-application bypass is an accepted limitation.

## DHCP and Local Reverse DNS Design

dnsmasq provides DHCP: authoritative leases for the segment, gateway/DNS options, optional static reservations, and lease-aware local names and PTR.

Interaction with Blocky: Blocky owns port 53; dnsmasq listens on a loopback-only alternate port for local reverse/host info; Blocky conditionally forwards the local reverse zone to dnsmasq. This keeps lease awareness in dnsmasq while Blocky stays the single client-facing resolver.

Reservations and local records: migrate the existing DHCP reservations and local DNS mappings from the current router/dnsmasq setup. Keep them as a single source of truth in a host-local data file, `hosts/soyo/reservations.nix` — a plain list of `{ name; mac; ip; }` — imported by both `hosts/soyo/dhcp.nix` (dnsmasq `dhcp-host` reservations, which also drive dnsmasq's PTR/reverse) and `hosts/soyo/dns.nix` (Blocky forward A records). Ownership is split cleanly: dnsmasq owns reverse/PTR (it is lease-aware, and Blocky forwards the reverse zone to it), Blocky owns forward A — both fed from the one file, so forward, reverse, and lease stay consistent from one edit. One illustrative entry: `{ name = "nas"; mac = "aa:bb:cc:dd:ee:ff"; ip = "10.0.0.10"; }`. MAC and IP values are LAN identifiers, not secrets, so the file is committed in plaintext (no agenix). The provisioning guide verifies the migrated reservations against the current router/dnsmasq before DHCP cutover.

AdGuard Home was evaluated as a single-module alternative and rejected; see the appendix.

## Unlock and Power-Loss Recovery

A primary design concern. TPM2 auto-unlock is the primary path so normal power loss recovers unattended; manual and remote unlock are break-glass only.

### Primary: TPM2 Auto-Unlock

A LUKS2 keyslot is enrolled to the TPM2 with `systemd-cryptenroll`, bound to PCRs representing a trusted boot.

- every normal boot (including after power loss) unlocks with no operator action; Soyo resumes DNS/DHCP within about a minute
- a passphrase keyslot is always kept as fallback

PCR caveat: firmware, bootloader, kernel, or initrd changes alter the measured boot and can invalidate the TPM policy until re-enrolled — expected, not a defect. Re-enrollment is a documented post-update step; break-glass covers the gap.

Security note: TPM unlock without a PIN protects against offline disk theft, not against someone powering on or stealing the running box — which matches a home-appliance threat model. A TPM PIN would strengthen it at the cost of a manual step.

### PCR Binding and Secure Boot

The binding changes across the two phases: **PCR 7** in Phase 1 (Secure Boot state), then **PCR 0+2+7** from Phase 2 on (adds core firmware and option ROMs). Kernel/initrd/cmdline integrity comes from Limine's Secure Boot chain plus the enrolled config and checksum validation — not from a measured PCR — which is what lets auto-unlock survive updates.

PCR rules:

- never bind **PCR 9**: under Secure Boot Limine measures the kernel image and config there, so it changes every kernel update and breaks unattended auto-unlock
- avoid **PCR 8**: it measures the cmdline and kernel/initrd paths, which are per-generation Nix store paths; the cmdline is already protected by the enrolled config, so it is not needed
- Phase 1 binds **PCR 7 only** (Secure Boot off, lowest churn); Phase 2 binds **PCR 0+2+7** for firmware/option-ROM tamper detection. Both are stable across kernel/initrd/bootloader updates; binding PCR 0+2 in Phase 1 would only add BIOS-update re-enroll churn with no integrity gain while Secure Boot is off

In Phase 1, before Secure Boot is on, the binding is convenience encryption against disk theft only: a hands-on attacker could edit the kernel cmdline (`rd.break`, `init=/bin/sh`) and the TPM would still release the key.

**Phase 1 — TPM convenience, no Secure Boot.** Run Limine without Secure Boot and enroll the TPM keyslot against PCR 7. Gives unattended power-loss recovery and encryption-at-rest against disk theft. Explicitly the weaker posture and a stepping stone.

**Phase 2 — Limine Secure Boot.** Limine's trust model: it signs its own binary, enrolls the config hash into that signed binary, and verifies kernel/initrd by checksum against it. Setting `boot.loader.limine.secureBoot.enable = true` makes the nixpkgs module enforce the safe settings automatically — it force-enables `enrollConfig`, `validateChecksums`, and `panicOnChecksumMismatch` and asserts the boot-entry editor is off, failing the build otherwise — so the config cannot be enabled insecurely. Remaining operator steps:

- generate keys with `sbctl`, put firmware into setup mode, enroll with Microsoft keys kept (`sbctl enroll-keys -m`) so option ROMs and vendor firmware still load (much lower brick risk)
- re-enroll the TPM keyslot against PCR 0+2+7

This closes the cmdline-injection bypass: the editor is gone and the cmdline is enrolled into the signed binary, so a tampered boot fails before the TPM would release the key.

Maintenance and recovery:

- kernel/initrd/bootloader updates leave PCR 0+2+7 unchanged; auto-unlock continues
- a BIOS/firmware update can change PCR 0 or clear keys; if so, re-enroll the Secure Boot keys and re-run `systemd-cryptenroll`
- if Secure Boot blocks boot during setup, toggle it off in firmware, boot, fix; the passphrase keyslot is an independent fallback throughout

Known caveats: `fwupd` is currently broken under Limine Secure Boot (nixpkgs #534574), so LVFS firmware updates may need Secure Boot temporarily off; the module boots a `bzImage`, not a UKI (a backlog migration that would only strengthen this).

### Break-Glass: Manual Unlock

Used only when TPM unlock cannot proceed (PCR change after an update, cleared TPM, disk moved, or fresh install before enrollment) — rare and operator-timed. Three ways in, all entering the LUKS passphrase via the systemd password flow:

- local console — keyboard and monitor, if the box is reachable
- LAN initrd SSH — SSH to the static LAN IP when the router/LAN is up and you are on the LAN
- direct-link rescue — for a headless box when the LAN path is unavailable (router/switch down, or no monitor handy): the initrd also serves a second dedicated static address on the wired port, reached by a laptop connected directly over Ethernet. Depends on no router DHCP/DNS or Wi-Fi — raw IP only. The rescue laptop uses a documented static profile (its own address in the same direct-link subnet). With Soyo's single Ethernet port, move the cable from the router/switch to the laptop for the unlock, then back afterward.

The direct-link path matters because Soyo is typically headless and may sit away from a monitor: it lets the operator rescue with just a laptop and an Ethernet cable, independent of the rest of the network.

### BIOS Prerequisites

Verified at provisioning:

- "State After G3" = S0, so Soyo powers on after an outage (confirmed)
- TPM 2.0 enabled, CRB interface (confirmed)
- CSM/Legacy off, UEFI-only boot (confirmed)
- Phase 2 Secure Boot: set Secure Boot Mode to **Customized**, use **Reset to Setup Mode** to clear keys, enroll from Linux with `sbctl enroll-keys -m`, then enable Secure Boot; **Install Factory Default Keys** restores the vendor/Microsoft keys to back out (confirmed available)

### Power-Loss Procedure

Normal: nothing to do — Soyo powers on, the TPM unlocks, DNS/DHCP resume in about a minute; confirm via the Synology probe.

Break-glass (only if auto-unlock failed):

1. confirm Soyo powered on; if not, check the BIOS AC-power-recovery setting
2. unlock with the passphrase via the reachable path: local console, LAN initrd SSH, or — if the LAN is down or the box is headless — direct-link rescue (laptop on the rescue static profile, Ethernet straight into Soyo, SSH to the direct-link initrd address)
3. wait for full boot; if recabling was needed, reconnect Soyo to the LAN
4. if the cause was a PCR change after an update, re-enroll the TPM keyslot

### Persistence for Unlock Identity

The initrd SSH host key should keep a stable fingerprint across rebuilds so the operator's `known_hosts` keeps working. The initrd runs before LUKS is unlocked, so this key cannot live on `persist` or anywhere inside the encrypted container. It must live unencrypted — a fixed path on the EFI/boot partition referenced by `boot.initrd.network.ssh.hostKeys`, copied into the initrd at build, distinct from the stage-2 host key. A clean reinstall regenerates it unless preserved, so expect to update `known_hosts` after a reinstall (or manage the key as a backed-up secret for cross-reinstall stability). It only authenticates the pre-unlock SSH endpoint; it does not protect data at rest.

## First Provisioning Workflow

Primary path: local install from a NixOS installer USB stick, because it needs no separate control machine — just the stick, internet, and the GitHub repo. Remote `nixos-anywhere` is the alternative for remote or multi-host setups.

### USB-Driven Local Provisioning (primary)

Assumes Soyo boots the installer USB, the live environment has internet, and GitHub is reachable.

1. boot the installer from USB
2. connect to the network
3. fetch the flake from GitHub
4. run `nixos-facter` to generate/confirm `hosts/soyo/facter.json`, and confirm target disk identifiers
5. run the `disko` disk setup from the flake
6. install from the fetched flake
7. reboot into the installed system
8. complete agenix recipient enrollment and secret refresh if needed
9. verify the migrated DHCP reservations and local DNS records against the current router/dnsmasq config before disabling router DHCP

Install-time networking caveat: the live environment must have `dwmac_motorcomm` (Linux 6.13+) to bring up `enp1s0`. The 26.05 ISO's kernel has it. Fallback: WiFi (`RTL8852BE` in-tree) or a USB Ethernet adapter.

Two acceptable operator models:

- full provisioning in one pass, when the agenix decryption material is available during install
- bootstrap then finalize — install first, then enroll secrets and redeploy from a trusted workstation

### Alternative: Remote Provisioning with nixos-anywhere

For another machine on the LAN, or adding hosts later:

1. prepare repo and secrets on the operator machine
2. boot the target into a NixOS installer with SSH access
3. run `nixos-anywhere` against it, letting `disko` partition and format
4. complete first boot, enroll the host recipient for agenix, re-encrypt secrets if needed, redeploy

Plain manual installation at the console remains a last-resort fallback.

## Local CLI Workflow

An intentionally small toolchain.

Required: `nixos-anywhere` (alternative remote install), `agenix` (secret create/edit/rekey), `treefmt-nix` (formatting), `deadnix` (dead-code lint). Day-2 remote deploys use native `nixos-rebuild --target-host` — local build on the workstation, closure copied, remote activation (no `--build-host`, so the N150 never builds) — first-class, no extra input.

Optional: `agenix-rekey` (future migration path beyond plain `agenix`), `deploy-rs` (M4 multi-host deploy orchestration), `nh` (rebuild/cleanup convenience) — the canonical documented workflow must still work with plain `nix` and `nixos-rebuild`.

Expose the required tools in a dev shell and wire formatting/linting into `nix flake check` where practical.

## Optional External Services

Third-party/off-box services (distinct from on-Soyo Future Services). Optional only — the core system must stay provisionable, recoverable, and operable without any external service beyond fetching the repo when the provisioning path needs it.

- GitHub Actions — CI for formatting, linting, host build checks; improves review without entering the runtime dependency chain
- Tailscale — post-boot remote admin; secondary to the LAN and local-console recovery paths
- Grafana Cloud with Grafana Alloy, or an external Prometheus/Grafana pair — alternative to the on-box Grafana + Loki + Tempo stack (useful for multi-host or off-box dashboards)
- Cachix (conditional) — binary cache if the repo later benefits, especially with CI builds or more hosts; only if its free-tier/visibility terms fit

No hosted service is required for: first boot, remote unlock, local power-loss recovery, secret decryption on target, or ordinary LAN DNS/DHCP.

## Router Preparation

Generic guidance that works with the Orbi RBK53 and other home routers:

- keep the router as gateway and Wi-Fi provider
- choose Soyo's static IP before switching DHCP authority
- disable router DHCP only when Soyo is ready to take over
- keep a documented way to re-enable router DHCP if needed

Describe concepts generically and note where Orbi-specific UI wording differs.

## Maintenance Defaults

- scheduled `nix.gc` and store optimisation
- bootloader generation limit
- periodic Btrfs scrub
- persistent journald with a bounded `SystemMaxUse`
- time sync (`timesyncd`)
- `systemd.tmpfiles` rules for persistent and secret-related paths
- ntfy failure notifications
- proactive free-space monitoring with an ntfy alert (e.g. at 85%)
- `smartd` with scheduled short and long self-tests

Failure notification and health-check detail is in Reliability and Observability.

### Updates

Easy path to the newest `nixos-unstable`:

- `flake.lock` is the authoritative pin
- a documented command/wrapper updates the `nixpkgs` input
- M1/M2 remote deploys use native `nixos-rebuild --target-host` (local build on the workstation, remote activation); `deploy-rs` (deploy checks wired into `nix flake check`) is deferred to M4 multi-host
- local break-glass path remains `nixos-rebuild test|switch`
- rollback documented alongside update
- kernel is `linuxPackages_latest` — no separate pin; after each nixpkgs update confirm `enp1s0` still comes up

Default policy is manual but easy; unattended updates are out of scope.

### Repository Hygiene Checks

Routine local verification: formatting, Nix lint, host build evaluation — first set `treefmt`, `deadnix`, and host build checks.

## Reliability and Observability

How Soyo stays up and how the operator learns when it does not. Complements the single-point-of-failure stance in Host Role and the runbooks in Disk and Hardware Failure; Error Handling is the consolidated failure-class index.

### Failure Notifications

Silent failure is the real risk. Soyo pushes to an ntfy topic so the operator learns of problems without looking:

- `systemd` `OnFailure` posts to ntfy for scrub, `nix.gc`, and any failed unit
- restic backup failures notify explicitly
- `smartd` notifies on SMART errors

The topic/URL is host-local config; any token is an agenix secret. A single lightweight push channel, not a full monitoring stack.

### Health Checking

ntfy is self-reported and cannot fire for total failure (panic, dead PSU, hung kernel) — the most important case for the LAN's only resolver. Three layers, each catching what the others cannot:

1. self-heal — Blocky and dnsmasq units use `Restart=on-failure`
2. self-reported — the ntfy notifications above, when the box is alive but something failed
3. external liveness probe — the always-on Synology DS423+ runs Uptime Kuma and probes Soyo from an independent failure domain: ICMP plus a DNS query against port 53 to prove Blocky answers (optionally a DHCP check), alerting via the Synology when probes fail

The Uptime Kuma watcher is NAS-side, documented as an operator step, not in the flake (like the off-site backup). A LAN-local watcher cannot report a whole-house outage where both boxes are down; that is accepted, with an optional external dead-man's switch if wanted later.

### Metrics

Soyo should expose metrics, but it should not become its own metrics stack.

- on-box exporters stay lightweight: Blocky's Prometheus endpoint, `node_exporter` for host metrics, and the Prometheus dnsmasq exporter for lease/DNS statistics
- Grafana, Prometheus, Loki, Tempo, and Alloy run **on-box** as resource-isolated guest services with `MemoryMax` and `CPUQuota` limits. This was initially designed as off-box (see [design journey](/docs/learning/design-journey.md)), but on-box was chosen for simplicity — Soyo's 16 GB RAM and single-NIC workload have ample headroom, and ruling out an off-box dependency keeps DNS/DHCP availability independent of NAS or WAN connectivity.
- alerting routes through Grafana's ntfy contact point (disk space, backup failure, service health)

That split preserves appliance focus: Soyo publishes a small metrics surface, while every heavier observability responsibility lives in an independent failure domain.

## Data and Backup Strategy

First-class, on a 3-2-1 intent: live data on Soyo, a local point-in-time copy, and an off-host copy on the Synology DS423+, with GitHub as the independent off-host copy of all declarative config.

### Data Classes

Classify everything on disk and treat each by its recovery model:

1. Declarative config — flake, NixOS modules, Home Manager dotfiles → rebuild from GitHub; no NAS copy
2. Secrets and recovery material — agenix secrets, operator key, host key, LUKS header → encrypted in repo plus offline backups (see Secrets and Users)
3. Real persistent data — non-derivable data declared in the persisted-path inventory (system paths restored from `persist`, plus real non-HM-managed user data) → restore from backup: restic to the Synology, plus local Btrfs snapshots
4. Derivable/disposable — `/nix`, caches, short-lived logs → regenerated by rebuild; no backup

Discipline: anything not reproducible from GitHub and not in classes 1–2 is class 3 and must be backed up.

### Local Snapshots

`btrbk` schedules read-only Btrfs snapshots into the `snapshots` subvolume for fast rollback and quick file recovery. Not a backup (same encrypted disk); retention short and bounded so snapshots do not fill the volume.

### Off-Host Backups to the Synology DS423+

`restic` via `services.restic.backups` pushes class 3 data to the Synology:

- encrypted and deduplicated at rest, so it is safe on a shared NAS
- repo password is an agenix secret
- transport is SSH/SFTP to a dedicated NAS backup user
- scheduled (e.g. daily) with a documented retention/`prune` policy; the module wires the `systemd` timer, pruning, and `OnFailure` → ntfy
- sourced from a stable Btrfs snapshot where practical for consistency

Tooling note: `restic` is chosen over `rustic` and `kopia` specifically because it is the only one of the three with a first-class NixOS module (`services.restic.backups`); `rustic`/`kopia` would mean hand-rolling systemd timers for no integration gain. `rustic`'s restic-compatible repo format stays a documented escape hatch if the client ever needs to change. Backed-up paths live in an easy-to-edit host-local list so the operator can add data locations as the role grows.

### NAS-Side and Off-Site

The Synology copy is the primary off-host backup, but one NAS is one failure domain:

- the NAS runs its own RAID/SHR redundancy and periodic scrub
- recommend the NAS replicate critical backups off-site (Synology Hyper Backup to cloud or a rotated external drive)
- the off-site step is the NAS operator's responsibility, noted not implemented here

### Restore Drill

A backup never restored is not a backup. Document a restore procedure and a periodic drill: list restic snapshots, restore a known test path to scratch, verify the content matches.

## Disk and Hardware Failure

Single disk, no RAID — a deliberate appliance choice. There is no redundancy to limp on, so verified backups are the entire resilience story; detection and backup verification matter more, not less. A mirrored Btrfs RAID1 is a possible future option contingent on a second M.2 slot, deferred because single-disk plus restic already covers the failure for less weight.

### Low Disk Space

A full root breaks the appliance (no leases, no rebuild, services fail) — a LAN outage. Defenses:

- bounded growth: `nix.gc` + generation limit, bounded snapshot retention, journald `SystemMaxUse` cap
- proactive ntfy free-space alert before full
- Btrfs caveat: `df` is misleading — watch `btrfs filesystem usage`, track data and metadata separately, and handle metadata exhaustion with apparent free space via `btrfs balance`

Recovery from near-full: drop old snapshots, delete old generations, then balance if metadata is the cause.

### SMART Warning, Disk Still Alive

`smartd` runs scheduled self-tests and alerts via ntfy. A warning triggers: verify the latest restic backup restores, procure a replacement disk, and treat the disk as on borrowed time. With no RAID, this is the main early signal before data loss.

### Disk or Full Hardware Replacement

Reuses the provisioning path:

1. provision via the USB install or `nixos-anywhere`, with `disko`, from the flake
2. restore class 3 data from the Synology restic repo
3. re-enroll agenix: new host key, add as recipient, rekey
4. for a new machine, update changed host-local facts: disk IDs, interface names, DHCP reservations keyed to the old NIC MAC

The reproducible flake + off-host backups + offline keys make a replacement host rebuildable from GitHub, the Synology, and the offline keys.

### NIC Failure

The onboard `yt6801` is a single port. If it fails, the fallback is a USB Ethernet adapter — keep a known-working one on hand. The onboard `RTL8852BE` WiFi (in-tree) can give emergency management access to diagnose a failed wired port, but cannot serve the wired LAN DHCP/DNS role, so the USB adapter is the way to restore service.

## Validation and Rehearsal

Post-install checklist:

- host builds from the flake
- `enp1s0` comes up (in-tree `dwmac_motorcomm` driver)
- host reaches the static LAN IP
- `ssh` by IP works
- `ssh soyo.home.arpa` resolves and works from a DHCP client
- `ssh soyo` works via the pushed search domain
- DHCP leases are handed out by Soyo
- clients receive the expected DNS server and gateway options
- Blocky answers from cache and upstream forwarding
- ad/tracker filtering blocks a known test domain
- local reverse lookups work
- a forced unit failure delivers an ntfy notification
- the Synology Uptime Kuma probe reports Soyo's DNS down when Soyo is powered off
- a simulated low-free-space condition triggers the ntfy threshold alert
- `smartd` self-tests are recorded and a forced warning notifies
- TPM2 auto-unlock succeeds on a normal reboot
- TPM2 auto-unlock still succeeds after a kernel/initrd update (PCR 0+2+7 stable)
- break-glass passphrase unlock works when the TPM keyslot is bypassed
- Phase 2: `sbctl status` shows Secure Boot on and signed; the editor is off; a tampered checksum or edited cmdline fails to boot
- initrd SSH host key fingerprint is stable across a rebuild
- LAN initrd SSH break-glass unlock works
- local console passphrase unlock works
- direct-link rescue unlock works from a laptop wired straight into Soyo, with the LAN path down
- TPM re-enrollment restores auto-unlock after a deliberate PCR change
- local Btrfs snapshots are created on schedule
- a restic backup runs to the Synology
- a restic restore drill recovers a known test path
- rollback path is understood and documented

Rehearse the full power-loss unlock path before relying on the system.

## Error Handling and Failure Strategy

Consolidated failure-class index:

- normal power loss → TPM2 auto-unlock; reboots and resumes unattended
- TPM auto-unlock fails (PCR change, cleared TPM) → break-glass passphrase unlock (local console or LAN initrd SSH), then re-enroll
- router/LAN down while a manual unlock is needed → local console, or direct-link rescue (laptop + Ethernet straight into Soyo) if the box is headless; both independent of the router/LAN
- bad `nixos-unstable` update → rollback and preserved boot entries
- reinstall after disk replacement → USB install or `nixos-anywhere`, with `disko` + agenix bootstrap
- operator machine lacks a DHCP lease during LAN recovery → documented temporary static-IP profile
- data loss/corruption of real data → Btrfs snapshots for recent mistakes, restic restore for larger loss
- Synology unavailable during a backup window → restic resumes incrementally next run; snapshots cover the gap locally
- Soyo fully down → long DHCP leases for short outages, router-DHCP re-enable for prolonged ones
- Soyo does not power on after an outage → BIOS AC-power-recovery setting
- silent operational failure (broken backup, failing disk) → ntfy notifications and `smartd`
- total failure that cannot self-report (panic, dead PSU) → external Synology Uptime Kuma probe
- low disk space → bounded-growth defaults, ntfy free-space alert, Btrfs-aware runbook
- SMART warning → `smartd` alerts, backup verification, disk replacement
- onboard NIC failure → USB Ethernet adapter fallback

## Future Extensibility

Structured so a future gaming laptop adds without restructuring the tree:

- keep base modules independent from server-only modules
- avoid root-level server policies that desktop hosts must inherit
- keep Soyo networking/service choices under `hosts/soyo` or server modules

### Base Is Role-Neutral

The rule that keeps a laptop drop-in: `modules/nixos/base.nix` and `modules/home/base.nix` stay ruthlessly role-neutral. Anything differing between a server appliance and a gaming laptop is forbidden in base and lives in a role module or host. Base must not assume:

- a network backend — `systemd-networkd` is a server choice (server module/host); a laptop uses NetworkManager
- a swap policy — `zramSwap`/no on-disk swap is a server choice; a laptop needs a real swap partition for hibernate, decided per host in disko
- a headless or GUI environment — base carries no display assumptions

### Planned Module Paths for a Laptop

Additive, not a restructuring — new aspect modules and a new host dir:

- `modules/nixos/desktop.nix` — Wayland, GPU/NVIDIA, audio, gaming aspect(s)
- `modules/home/desktop.nix` — Home Manager aspect layered on `modules/home/base.nix`
- `hosts/laptop/` — its own `facter.json`, `boot.nix`, `disko.nix`, `networking.nix`
- a new agenix host key, recipient, and rekey for any secrets it needs

The laptop reuses the base, users, and `modules/home/base.nix` aspects, the backup aspect, and the disko pattern unchanged; it simply doesn't toggle on the DNS, DHCP, or remote-unlock aspects.

The first implementation adopts Home Manager as a small headless server profile only — no desktop, GUI, or theming.

## Future Services on Soyo

Soyo is likely to grow into a small home server (e.g. Jellyfin) with the Synology DS423+ kept as storage. Anticipated, not implemented in the first version. This section is intentionally detailed as a planning reference for later phases (M4), not first-implementation scope; the rules below keep the door open without building ahead of need:

- compute on Soyo, storage on Synology — services run on Soyo; bulk data (media) stays on the DS423+ over NFS, keeping Soyo's disk small
- prefer native NixOS modules (e.g. `services.jellyfin`); fall back to a container only where no native module exists; each service its own opt-in aspect at `modules/nixos/<name>.nix` (exposing `flake.modules.nixos.<name>`), toggled on per host
- use the Intel N150 iGPU (QuickSync via `renderD128`/VAAPI) for hardware transcoding
- give each service a local `home.arpa` Blocky record, with a reverse proxy (e.g. Caddy) and internal TLS once there is more than one web service
- back up service state (databases, config) as class 3 via restic; media on the Synology is the NAS's backup job
- reassess RAM/CPU headroom and the widened outage blast radius when adding services, though DNS/DHCP remain the only critical roles; service state on a near-full disk is also why free-space monitoring matters

### Resource Isolation Rule

DNS and DHCP stay sacred; every other service is a guest. Each added service runs opt-in under systemd with `MemoryMax`, `CPUQuota`, and lowered `Nice`/`IOWeight`, so a misbehaving or busy service is constrained from starving Blocky or dnsmasq under normal conditions. These limits reduce risk but do not cover every shared bottleneck (disk I/O saturation, kernel locks), so a genuinely heavy guest still warrants its own host.

### Candidate Services (quick notes)

The "fits this box" profile: light, always-on, trusted-LAN, state small or on the NAS.

- media — **Jellyfin** (FOSS) or **Plex** (you have a lifetime Plex Pass, so QuickSync HW transcode is unlocked); both use the N150 iGPU via `renderD128`, libraries on the NAS over NFS. Plex is proprietary and account-tied, Jellyfin is FOSS — pick one. **Navidrome** for music.
- **Home Assistant** — native module is HA *Core* (no Supervisor/add-on store); USB Zigbee/Z-Wave coordinator plus onboard Bluetooth; HA ships its own zeroconf (independent of the dropped system Avahi); state in `/var/lib/hass` → restic
- **Immich** (photos) — useful but the heaviest "fit": its ML (face/object detection, thumbnails) is CPU/RAM-hungry on an N150, so isolate it hard, throttle or off-peak the ML jobs, expect a slow first index, and keep originals on the NAS; watch contention with DNS/DHCP
- **Vaultwarden** — self-hosted Bitwarden; tiny, high-value, small state → easy backup; behind Tailscale, never WAN-exposed
- **Tailscale subnet router** — remote access to the whole LAN with no inbound port; and when Tailscale DNS is pointed at Soyo/Blocky, the filtered DNS follows you off-network
- **API-based AI agent** — an orchestrator (Hermes-style or similar) that calls cloud LLM APIs is light, just HTTP, so it fits as a guest; distinct from local inference, which is an anti-goal
- **chrony** — serve LAN NTP; tiny and infra-appropriate, same category as DNS/DHCP
- **Nix binary cache** (`attic`/`harmonia`) — build once on Soyo, serve store paths to the laptop. Must be size-contained on the 512 GB SSD: store the cache on the NAS, or if local cap it with attic retention/GC so it cannot grow unbounded
- **Backup relay / Syncthing** — Soyo as a restic target or Syncthing node so the laptop reaches the NAS through it

### Not on This Box (anti-goals)

- **local LLM inference** (Hermes weights, Ollama, etc.) — no usable GPU, fixed 16 GB RAM, and it would contend with DNS/DHCP; run local models on the GPU laptop or a dedicated GPU host. An API-based agent calling cloud LLMs is fine (see candidates) — only on-box inference is excluded
- **CPU-bursty workloads** — game servers, CI runners, heavy databases
- **anything WAN-inbound** — the design is LAN-only; reach in via Tailscale

## Hardware Facts and Open Constraints

Confirmed on the unit from a NixOS live environment:

- Intel N150 (4 cores), 16 GB RAM, iGPU (`/dev/dri`: `card1`, `renderD128`) — QuickSync available for a future Jellyfin; comfortable headroom for DNS/DHCP
- Ethernet: Motorcomm `YT6801` (`1f0a:6801`), Gigabit. In-tree `dwmac_motorcomm` driver (Linux 6.13+). Confirmed working on the 26.05 live ISO. Expected wired interface `enp1s0` (PCI `01:00.0`)
- WiFi: Realtek `RTL8852BE` on `wlp2s0`, driver `rtw89_8852be`, in-tree on 6.19.3
- target disk: SATA SSD at `/dev/disk/by-id/ata-PELADN_512GB_20250522100164` (~512 GB) — use this by-id in `disko`
- TPM2 present and usable: firmware TPM (`MSFT0101`, `tpm_crb`), v2, visible to `systemd-cryptenroll`
- Secure Boot currently disabled (Standard mode); firmware supports a **Customized** mode that exposes "Reset to Setup Mode", "Key Management", and "Install Factory Default Keys" — so Phase-2 custom-key enrollment is supported (confirmed in BIOS)

Remaining unknowns:

- whether the chassis has a second disk slot (only for the deferred RAID1 option)
- final DHCP reservations and any deviations from the example ranges (host-local config)

These do not change the design direction.

## Recommended Implementation Direction

A small, focused custom flake that borrows patterns from established NixOS repos without forking any large personal repo.

Borrow: `flake-parts` with the dendritic pattern (`import-tree`, aspect modules) and thin host dirs; declarative hardware via `nixos-facter`; `nixos-anywhere` install; `disko` layout; `preservation` with a blank-snapshot rollback and a documented persisted-path inventory; `agenix-rekey`'s `rekeyFile` flow (used from day one — master-encrypted files rekeyed per host at build time); native `nixos-rebuild --target-host` for routine remote activation (`deploy-rs` deferred to M4); systemd-native server/initrd patterns; TPM2 auto-unlock via `systemd-cryptenroll` hardened by Limine Secure Boot; headless Home Manager on a shared base; declarative `restic` backups via `services.restic.backups`.

Avoid: desktop policy; broad self-hosting stacks; ZFS; legacy initrd shell hacks; over-automation of unattended updates.

## Deliverables for the Implementation Phase

1. New `flake.nix` on `flake-parts` + `import-tree` with `nixos-facter-modules`, `disko`, `preservation`, `agenix`, and `home-manager` inputs, plus optional operator tooling such as `agenix-rekey` (`deploy-rs` added at M4)
2. Dendritic aspect-module tree (base, server, service, user, Home Manager aspects in `flake.modules.*`), with each host toggling the aspects it uses
3. `hosts/soyo` host assembly
4. Boot config using `linuxPackages_latest` — in-tree `dwmac_motorcomm` driver, no pin needed
5. Encrypted Btrfs `disko` definition with `root`/`root-blank` subvolumes and an initrd blank-snapshot rollback for the impermanent root
6. Limine config plus TPM2 auto-unlock: Phase 1 enrolls `systemd-cryptenroll` against PCR 7 with a passphrase fallback; Phase 2 enables Limine Secure Boot (`secureBoot.enable`, `sbctl` keys with Microsoft keys kept) and re-enrolls the TPM against PCR 0+2+7, with documented rollback/recovery steps
7. agenix secret layout and example password-hash onboarding, with the future `agenix-rekey` migration path documented but not required for M1/M2
8. Blocky and dnsmasq modules
9. systemd initrd break-glass unlock module: LAN address plus direct-link rescue address, with local console also available
10. Headless Home Manager profile for the admin user, with user persistence declared explicitly
11. Backup aspect: restic to the Synology via `services.restic.backups`, plus scheduled Btrfs snapshots
12. Observability module: Blocky metrics retained, plus `node_exporter`, dnsmasq exporter, and on-box Grafana+Prometheus+Loki+Tempo+Alloy as resource-isolated guest services with Grafana alerting (disk, backup, service health) routed through ntfy
13. ntfy failure-notification wiring for systemd units and smartd (in maintenance.nix); backup alerts now route through Grafana
14. Update/deploy workflow on native `nixos-rebuild` (`--target-host` for remote: local build + remote activation; `test|switch` locally), with `nh` only as local convenience; `deploy-rs` deferred to M4
15. Operator docs for install, update, validation, backup/restore, and outage recovery
16. Learning-oriented documentation (first-class, see Learning Goals): a design-journey narrative deriving the design from basics through its important transient steps and rejected alternatives, a guided entry-point doc with an explicit reading order mapped to M1–M4, a glossary of the repo's non-obvious terms, per-concept explainer notes each linked to a canonical source (nix.dev, NixOS/Nixpkgs/Home Manager manuals, `flake.parts`, search.nixos.org), an explicit explanation of the dendritic aspect→host wiring, and modules commented with the idiom and the *why*

## Implementation Roadmap

Build order, each milestone independently buildable and validatable. The production cut-line is the end of M2; M3 hardens; M4 expands.

Before touching hardware, rehearse the host build and disk layout in a VM (`nixos-rebuild build-vm`, `disko` VM test) to catch boot/partition/initrd mistakes off the real box.

### M1 — Bootable appliance (MVP)

- flake-parts + `import-tree` dendritic skeleton with base + server + service aspects; `nixos-facter` hardware report committed
- `disko`: LUKS2 + Btrfs with `root`/`root-blank` subvolumes on the `ata-PELADN_512GB_...` disk
- impermanent root via the initrd blank-snapshot rollback + `preservation`, with an explicit persisted-path inventory for host identity (incl. the agenix host key before decryption), declarative users, logs, and DHCP state
- `linuxPackages_latest` + in-tree `dwmac_motorcomm` driver; `systemd-networkd` static LAN on `enp1s0`
- Blocky (ad-block, DoT upstream, `bootstrapDns`) + dnsmasq (DHCP, reverse zone, `home.arpa` search domain)
- TPM Phase-1 auto-unlock (PCR 7, passphrase fallback), systemd initrd, Limine; initrd LAN + direct-link rescue addresses
- `root` + `krzysiek` users, key-only SSH policy

Outcome: serves DNS/DHCP on the LAN, restores the declared durable state after reboot, and unlocks unattended on power loss. Validate: `enp1s0` up, leases handed out, DNS resolves and filters, `soyo.home.arpa`, persisted identities survive reboot, TPM auto-unlock across a reboot.

### M2 — Durability and operations (production cut-line)

- agenix: password hashes, restic repo password, ntfy token; offline backup of operator key and LUKS header
- backups: restic to the Synology via `services.restic.backups` + `btrbk` snapshots + a tested restore drill
- maintenance defaults: `nix.gc`, scrub, journald cap, `smartd`, free-space monitoring
- reliability: ntfy `OnFailure` notifications; Synology Uptime Kuma probe
- observability: Blocky metrics, `node_exporter`, dnsmasq exporter, and an off-box scraper/dashboard path
- headless Home Manager profile; documented native `nixos-rebuild --target-host` deploy workflow (deploy-rs deferred to M4)

Outcome: backed up, observable, recoverable. Validate: restore drill, forced-failure ntfy, probe reports DNS down when powered off.

### M3 — Security hardening

- BIOS: Secure Boot Mode → Customized → Reset to Setup Mode
- `sbctl create-keys` + `enroll-keys -m`; `limine.secureBoot.enable`; enable Secure Boot; re-enroll TPM against PCR 0+2+7

Outcome: signed boot, cmdline-injection closed, auto-unlock surviving updates. Validate: `sbctl status` signed, tampered cmdline fails to boot, auto-unlock after a kernel update, re-enroll restores it after a deliberate PCR change.

### M4 — Expansion (later)

- gaming laptop host (`hosts/laptop`, desktop modules)
- `deploy-rs` for multi-host remote deployment (deploy checks, magic-rollback) once a second host justifies it over native `nixos-rebuild --target-host`
- future services on Soyo (Jellyfin etc.) over NFS to the Synology
- off-site NAS replication; RAID1 if a second disk slot exists

## Appendix: Alternatives Considered

### DNS/DHCP stack: AdGuard Home vs Blocky + dnsmasq

AdGuard Home (`services.adguardhome`) was evaluated as a single-module alternative (DNS, ad-blocking, DHCP, MAC→IP reservations via `settings.dhcp.static_leases`, local PTR).

| Priority | Better choice |
|---|---|
| Fewest moving parts, built-in UI, fast setup | AdGuard Home |
| No inter-daemon glue | AdGuard Home |
| Git-authoritative / declarative purity | Blocky + dnsmasq |
| DHCP depth and maturity | Blocky + dnsmasq |
| Component fault isolation | Blocky + dnsmasq (mild) |
| Resolver-level routing in config | Blocky + dnsmasq |

Not chosen because AdGuard is UI-first and rewrites its YAML (full declarative control needs `mutableSettings = false`, which fights the app, especially for DHCP, risking UI drift), its static-lease schema has churned across versions (version-fragile config), its DHCP server is young and thin next to dnsmasq, and a single process couples DNS and DHCP into one blast radius.

Decision: **Blocky + dnsmasq** — a git-authoritative flake, DHCP robustness, and first-class recovery outweigh the inter-daemon glue. Revisit only if operator simplicity and the built-in UI/query-log outrank declarative purity and DHCP depth.

### Flake organization: dendritic pattern

The dendritic pattern (every file a flake-parts module, aspect-oriented across classes, auto-imported with `import-tree`) is purpose-built for sharing across host classes. It was initially rejected as a generic framework built before the second host exists, a large novel concept atop the Home Manager learning goal, and a legibility cost via auto-import and aspect scattering — and legibility matters most for recovery.

Decision (revised): **adopt the dendritic pattern.** With the project reframed around learning radical-modern Nix, the pattern's educational value now outweighs the legibility cost, and that cost is mitigated by documenting the aspect→host wiring. The original counter-arguments are acknowledged as the price paid: recovery legibility leans on docs rather than flat imports, and the second host doesn't exist yet — accepted deliberately for the learning goal.

### Bootloader and Secure Boot: Limine vs lanzaboote

lanzaboote was the initial assumption. Limine was chosen: in-tree, CI-tested nixpkgs module with no external flake input, suiting an appliance tracking `nixos-unstable` for low maintenance — and nixpkgs dropped the `lanzaboote-tool` package in 2025 for lack of integration maintenance, with lanzaboote able to lag systemd on unstable. lanzaboote's edge is its audited single signed UKI, but Limine's module force-enables the safe settings under Secure Boot, so the configuration-correctness gap is small.

Revisit if Limine's Secure Boot integration regresses or a future host clearly needs the signed-UKI model; the phased approach keeps Phase 1 bootloader-agnostic.
