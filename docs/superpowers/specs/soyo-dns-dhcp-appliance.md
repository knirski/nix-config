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
- impermanence or stateless-root
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

The explicit-role-module layout (over dendritic) and Home Manager adoption support this: both keep the config legible and teach mainstream idioms.

## Key Decisions

Load-bearing choices at a glance; rationale and rejected alternatives are in the body and appendix.

| Area | Decision |
|---|---|
| Flake organization | `flake-parts` with explicit role modules (not full dendritic) |
| Filesystem | LUKS2 + Btrfs with zstd, subvolumes; no impermanence, no ZFS |
| Swap | `zramSwap`, no on-disk swap |
| Kernel | Pinned LTS (Linux 6.12) for the out-of-tree `yt6801` NIC module; userspace tracks unstable; switch to in-tree when yt6801 mainlines |
| DNS | Blocky (forwarding/caching + ad-block) on port 53 |
| DNS upstream | DoH to DNS4EU NoAds (general filtering) + Quad9 fallback; one local Polish blocklist; static-IP `bootstrapDns` |
| DHCP + local PTR | dnsmasq, reverse zone conditionally forwarded from Blocky |
| Secrets | agenix, hashed passwords, offline key/LUKS-header backup |
| User environment | Home Manager as a NixOS module, headless profile |
| Network backend | `systemd-networkd` (server-scoped, not in base) |
| Bootloader | Limine (in-tree nixpkgs module, CI-tested, no extra flake input) |
| Boot / unlock | TPM2 auto-unlock (primary), phased: PCR-7 convenience first, then Limine Secure Boot with PCR 0+2+7 (Microsoft keys kept); break-glass via local console, LAN initrd SSH, or direct-link rescue (laptop + Ethernet) |
| Backups | restic to Synology DS423+, local Btrfs snapshots, GitHub for config |
| Health checking | self-heal + ntfy OnFailure + Synology Uptime Kuma probe |
| Redundancy | single disk, no RAID; verified backups are the resilience story |
| Updates | manual but easy `nixos-unstable`; unattended out of scope |

## Chosen Tooling

- `flake-parts` — modular flake outputs and per-class module composition
- `disko` — declarative GPT, LUKS2, Btrfs layout
- `agenix` — encrypted secrets, including password hashes
- Home Manager — declarative per-user environment and dotfiles
- `restic` — encrypted, deduplicated off-host backups to the Synology DS423+
- `btrbk` — scheduled local Btrfs snapshots
- `nixos-anywhere` — alternative remote provisioning over SSH
- `treefmt-nix` — repo-wide formatting
- `deadnix` — unused-binding analysis
- `systemd-networkd` — runtime network manager
- systemd initrd networking + SSH — break-glass remote unlock
- Limine — UEFI boot and Secure Boot; in-tree nixpkgs module, no external flake input
- `systemd-cryptenroll` — TPM2-backed LUKS auto-unlock, passphrase keyslot kept as fallback
- `sbctl` — Secure Boot key management for Limine Phase 2
- Blocky — forwarding/caching DNS with local records, chosen for ad/tracker blocking
- dnsmasq — DHCP and lease-aware local reverse lookup

## Filesystem Choice

`LUKS2` with `Btrfs` inside the encrypted container, `zstd` compression, subvolume mounts.

- snapshots and subvolumes without ZFS-level operational weight
- `disko` models it cleanly
- Btrfs is in-tree on any kernel and needs no DKMS; ZFS is out-of-tree, and the host already carries one out-of-tree module (the NIC) — a second for the filesystem is undesirable

## Repository Structure

A multi-host flake from day one.

### Flake Organization

Built on `flake-parts`, with explicit host composition and role modules rather than the full dendritic pattern:

- `flake-parts` gives modular outputs (formatter, checks, dev shell, Home Manager) instead of one monolithic `flake.nix`
- hosts compose by explicit `imports` of role modules (`base`, `server`, `desktop`) and service modules, so each host file plainly lists what it is
- shared behavior lives in role and service modules that hosts opt into

The dendritic pattern was evaluated and not adopted; see the appendix.

### Top Level

- `flake.nix` — thin, on `flake-parts`; declares inputs (`flake-parts`, `home-manager`, `disko`, `agenix`); composes per-host `nixosConfigurations.<hostname>` from role/service modules with Home Manager as a NixOS module; exposes formatter, checks, dev shell, and any update/deploy helper apps
- `hosts/` — one directory per machine
- `modules/` — reusable NixOS modules by responsibility
- `secrets/` — agenix secret files and recipient mapping
- `docs/` — operator install, maintenance, recovery docs
- `scripts/` — thin update/deploy wrappers

### Proposed Module Layout

- `modules/base/default.nix` — common defaults shared across hosts
- `modules/nixos/server/default.nix` — server-only defaults
- `modules/nixos/services/blocky.nix` — DNS
- `modules/nixos/services/dnsmasq-dhcp.nix` — DHCP
- `modules/nixos/services/remote-unlock.nix` — shared initrd unlock building blocks
- `modules/nixos/services/maintenance.nix` — `nix.gc`, store optimisation, scrub, journald/boot-entry limits, `smartd`, free-space monitoring, ntfy notifications, time sync
- `modules/nixos/services/backup.nix` — restic jobs, snapshot scheduling, repo-secret wiring
- `modules/nixos/users/default.nix` — user policy and secret-backed passwords
- `modules/home/base.nix` — shared headless Home Manager profile

### Soyo Host Layout

- `hosts/soyo/default.nix` — assembles the host
- `hosts/soyo/hardware-configuration.nix` — generated hardware facts
- `hosts/soyo/boot.nix` — kernel, firmware, systemd initrd, TPM2 auto-unlock, Limine (Secure Boot in Phase 2)
- `hosts/soyo/disko.nix` — GPT, EFI, LUKS2 (with TPM2 crypttab option), Btrfs subvolumes
- `hosts/soyo/networking.nix` — static LAN addressing and firewall
- `hosts/soyo/initrd-unlock.nix` — initrd SSH and network: the static LAN address plus a second dedicated direct-link rescue address, for break-glass unlock
- `hosts/soyo/reservations.nix` — single source of truth: `{ name; mac; ip; }` list, imported by both `dhcp.nix` and `dns.nix`; plaintext (MAC/IP are not secrets)
- `hosts/soyo/dns.nix` — Soyo Blocky policy and forward A records from `reservations.nix` (reverse/PTR is dnsmasq's job)
- `hosts/soyo/dhcp.nix` — DHCP ranges, router options, and `dhcp-host` reservations from `reservations.nix`
- `hosts/soyo/users.nix` — host-specific user assembly if needed
- `hosts/soyo/home.nix` — Soyo Home Manager additions on the shared profile
- `hosts/soyo/backup.nix` — Soyo backup paths, schedule, Synology target

This separates machine facts from reusable service behavior, so a future laptop reuses base and user modules without inheriting server networking or unlock logic.

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
- a pinned LTS kernel the out-of-tree `yt6801` module builds against (see below)

### Kernel and NIC Driver

The onboard Ethernet is the Motorcomm `YT6801` Gigabit controller (`1f0a:6801`), with no in-tree driver: the mainline driver is still in review (net-next v4, April 2025), confirmed absent from the mainline tree and MAINTAINERS. The only working driver is the out-of-tree vendor module, packaged in nixpkgs as `yt6801` (v1.0.30), whose compat patches reach only 6.16 and which is reported broken on 6.17+. Confirmed on the unit: a 6.19.3 live environment binds no driver and shows no wired interface.

Decision: pin a kernel the `yt6801` module builds against and load it via `boot.extraModulePackages`. Pin the latest LTS in range — Linux 6.12 LTS — not a soon-EOL 6.16, to keep security backports. Userspace still tracks `nixos-unstable`; only the kernel is pinned via `boot.kernelPackages`.

- a pinned non-current kernel lags features and, once its series ends, security fixes — mitigated by choosing an LTS and by the host being LAN-only, not WAN-exposed
- TPM2, Btrfs, and Limine Secure Boot are all mature well before 6.12, so the pin costs nothing there
- exit path: when in-tree `yt6801` merges, move to a `nixos-unstable` kernel containing `drivers/net/ethernet/motorcomm/yt6801/`, drop the module, and unpin. The trigger is that path appearing in the running kernel.

## Disk Layout

`disko`: one GPT disk, one EFI System Partition, one LUKS2 partition, one Btrfs filesystem inside it.

Subvolumes and mount intent:

- `root` — OS root
- `nix` — `/nix`
- `persist` — state that must survive rollbacks and reinstalls, including the dnsmasq lease database so leases and reservation state survive reboots/rebuilds (no duplicate-IP handouts)
- `log` — persistent journald and related logs
- `snapshots` — local snapshot target

No impermanence in the first version; persistent directories are tracked explicitly and mounted from `persist`.

### Swap

`zramSwap`, no on-disk swap. With 16 GB RAM the box rarely needs swap; zram keeps any swap in the compressed memory path and avoids swap-on-Btrfs and swap-on-LUKS complications, so the disko layout needs no swap device.

## Secrets and Users

agenix, not sops-nix.

### Secret Model

- `secrets/secrets.nix` maps secrets to recipients
- encrypted password hashes: `secrets/root-password.age`, `secrets/krzysiek-password.age`
- recipients: the operator key (management machine) and the Soyo host key (after install)

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
- `modules/home/base.nix` holds the headless profile (shell, prompt, git, editor, CLI tools); `hosts/soyo/home.nix` layers Soyo additions
- headless only: no desktop, GUI, or theming
- manages config/dotfiles, not real user data (documents, app databases) — that is a backup concern

Because dotfiles are declarative and in GitHub, they need no NAS backup. Real data under the user's home is class 3 and backed up explicitly (see Data and Backup Strategy).

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
4. confirm hardware facts and target disk identifiers
5. run the `disko` disk setup from the flake
6. install from the fetched flake
7. reboot into the installed system
8. complete agenix recipient enrollment and secret refresh if needed
9. verify the migrated DHCP reservations and local DNS records against the current router/dnsmasq config before disabling router DHCP

Install-time networking caveat: the stock installer lacks the out-of-tree `yt6801` module (the unit's 6.19.3 live environment had no wired interface), so connect over WiFi (`RTL8852BE` works in-tree) or a USB Ethernet adapter; the onboard port works once the installed system runs the pinned kernel with `yt6801`.

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

Required: `nixos-anywhere` (alternative remote install), `agenix` (secret create/edit/rekey), `treefmt-nix` (formatting), `deadnix` (dead-code lint).

Optional: `nh` (rebuild/cleanup convenience) — the canonical documented workflow must still work with plain `nix` and `nixos-rebuild`.

Expose the required tools in a dev shell and wire formatting/linting into `nix flake check` where practical.

## Optional External Services

Third-party/off-box services (distinct from on-Soyo Future Services). Optional only — the core system must stay provisionable, recoverable, and operable without any external service beyond fetching the repo when the provisioning path needs it.

- GitHub Actions — CI for formatting, linting, host build checks; improves review without entering the runtime dependency chain
- Tailscale — post-boot remote admin; secondary to the LAN and local-console recovery paths
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
- supports `dry`, `test`, `switch` deployment
- rollback documented alongside update
- the kernel is deliberately pinned to an LTS for `yt6801` (see Kernel and NIC Driver), independent of the `nixpkgs` bump; a userspace update must not silently move the kernel, and after each update the `yt6801` module is confirmed built and `enp1s0` up

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

## Data and Backup Strategy

First-class, on a 3-2-1 intent: live data on Soyo, a local point-in-time copy, and an off-host copy on the Synology DS423+, with GitHub as the independent off-host copy of all declarative config.

### Data Classes

Classify everything on disk and treat each by its recovery model:

1. Declarative config — flake, NixOS modules, Home Manager dotfiles → rebuild from GitHub; no NAS copy
2. Secrets and recovery material — agenix secrets, operator key, host key, LUKS header → encrypted in repo plus offline backups (see Secrets and Users)
3. Real persistent data — non-derivable data on `persist` and real (non-HM-managed) data under the user's home → restore from backup: restic to the Synology, plus local Btrfs snapshots
4. Derivable/disposable — `/nix`, caches, short-lived logs → regenerated by rebuild; no backup

Discipline: anything not reproducible from GitHub and not in classes 1–2 is class 3 and must be backed up.

### Local Snapshots

`btrbk` schedules read-only Btrfs snapshots into the `snapshots` subvolume for fast rollback and quick file recovery. Not a backup (same encrypted disk); retention short and bounded so snapshots do not fill the volume.

### Off-Host Backups to the Synology DS423+

`restic` via `services.restic.backups` pushes class 3 data to the Synology:

- encrypted and deduplicated at rest, so it is safe on a shared NAS
- repo password is an agenix secret
- transport is SSH/SFTP to a dedicated NAS backup user
- scheduled (e.g. daily) with a documented retention/`prune` policy
- sourced from a stable snapshot where practical for consistency

Backed-up paths live in an easy-to-edit host-local list so the operator can add data locations as the role grows.

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
- the `yt6801` module builds against the pinned kernel and `enp1s0` comes up
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

The rule that keeps a laptop drop-in: `modules/base` and `modules/home/base.nix` stay ruthlessly role-neutral. Anything differing between a server appliance and a gaming laptop is forbidden in base and lives in a role module or host. Base must not assume:

- a network backend — `systemd-networkd` is a server choice (server module/host); a laptop uses NetworkManager
- a swap policy — `zramSwap`/no on-disk swap is a server choice; a laptop needs a real swap partition for hibernate, decided per host in disko
- a headless or GUI environment — base carries no display assumptions

### Planned Module Paths for a Laptop

Additive, not a restructuring:

- `modules/nixos/desktop/` — Wayland, GPU/NVIDIA, audio, gaming
- `modules/home/desktop.nix` — layered on `modules/home/base.nix`
- `hosts/laptop/` — its own `boot.nix`, `disko.nix`, `networking.nix`
- a new agenix host key, recipient, and rekey for any secrets it needs

The laptop reuses `modules/base`, `modules/nixos/users`, `modules/home/base.nix`, the backup module, and the disko pattern unchanged; it just does not import DNS, DHCP, or remote-unlock modules.

The first implementation adopts Home Manager as a small headless server profile only — no desktop, GUI, or theming.

## Future Services on Soyo

Soyo is likely to grow into a small home server (e.g. Jellyfin) with the Synology DS423+ kept as storage. Anticipated, not implemented in the first version. This section is intentionally detailed as a planning reference for later phases (M4), not first-implementation scope; the rules below keep the door open without building ahead of need:

- compute on Soyo, storage on Synology — services run on Soyo; bulk data (media) stays on the DS423+ over NFS, keeping Soyo's disk small
- prefer native NixOS modules (e.g. `services.jellyfin`); fall back to a container only where no native module exists; each service its own opt-in module under `modules/nixos/services/`
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
- Ethernet: Motorcomm `YT6801` (`1f0a:6801`), Gigabit. No in-tree driver; needs the out-of-tree `yt6801` module on a pinned kernel (see Kernel and NIC Driver). On 6.19.3 no driver binds and no wired interface appears. Expected wired interface `enp1s0` (PCI `01:00.0`) once the module loads
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

Borrow: `flake-parts` with explicit legible host composition; multi-host layout with thin host dirs; `nixos-anywhere` install; `disko` layout; `agenix` secret lifecycle; systemd-native server/initrd patterns; TPM2 auto-unlock via `systemd-cryptenroll` hardened by Limine Secure Boot; headless Home Manager on a shared base; declarative `restic` backups.

Avoid: desktop policy; broad self-hosting stacks; impermanence by default; ZFS; legacy initrd shell hacks; over-automation of unattended updates.

## Deliverables for the Implementation Phase

1. New `flake.nix` on `flake-parts` with `disko`, `agenix`, `home-manager` inputs
2. Module tree with shared base, server, service, user, and Home Manager modules, composed explicitly per host
3. `hosts/soyo` host assembly
4. Boot config pinning Linux 6.12 LTS and loading the out-of-tree `yt6801` module, with the documented switch to in-tree when it mainlines
5. Encrypted Btrfs `disko` definition
6. Limine config plus TPM2 auto-unlock: Phase 1 enrolls `systemd-cryptenroll` against PCR 7 with a passphrase fallback; Phase 2 enables Limine Secure Boot (`secureBoot.enable`, `sbctl` keys with Microsoft keys kept) and re-enrolls the TPM against PCR 0+2+7, with documented rollback/recovery steps
7. agenix secret layout and example password-hash onboarding
8. Blocky and dnsmasq modules
9. systemd initrd break-glass unlock module: LAN address plus direct-link rescue address, with local console also available
10. Headless Home Manager profile for the admin user
11. Backup module: restic to the Synology plus scheduled Btrfs snapshots
12. ntfy failure-notification wiring for systemd units, restic, and `smartd`
13. Update/deploy workflow leaning on `nh` and `nixos-rebuild`, thin scripts only where they add value
14. Operator docs for install, update, validation, backup/restore, and outage recovery
15. Learning-oriented documentation: modules commented with the idiom and the *why*, and per-concept notes that explain the Nix/NixOS concepts used, each linked to a canonical source (nix.dev, NixOS/Nixpkgs/Home Manager manuals, `flake.parts`, search.nixos.org)

## Implementation Roadmap

Build order, each milestone independently buildable and validatable. The production cut-line is the end of M2; M3 hardens; M4 expands.

Before touching hardware, rehearse the host build and disk layout in a VM (`nixos-rebuild build-vm`, `disko` VM test) to catch boot/partition/initrd mistakes off the real box.

### M1 — Bootable appliance (MVP)

- flake-parts skeleton with base + server + service role modules
- `disko`: LUKS2 + Btrfs subvolumes on the `ata-PELADN_512GB_...` disk
- pinned Linux 6.12 LTS + out-of-tree `yt6801` module; `systemd-networkd` static LAN on `enp1s0`
- Blocky (ad-block, DoT upstream, `bootstrapDns`) + dnsmasq (DHCP, reverse zone, `home.arpa` search domain)
- TPM Phase-1 auto-unlock (PCR 7, passphrase fallback), systemd initrd, Limine; initrd LAN + direct-link rescue addresses
- `root` + `krzysiek` users, key-only SSH policy

Outcome: serves DNS/DHCP on the LAN and unlocks unattended on power loss. Validate: `enp1s0` up, leases handed out, DNS resolves and filters, `soyo.home.arpa`, TPM auto-unlock across a reboot.

### M2 — Durability and operations (production cut-line)

- agenix: password hashes, restic repo password, ntfy token; offline backup of operator key and LUKS header
- backups: restic to the Synology + `btrbk` snapshots + a tested restore drill
- maintenance defaults: `nix.gc`, scrub, journald cap, `smartd`, free-space monitoring
- reliability: ntfy `OnFailure` notifications; Synology Uptime Kuma probe
- headless Home Manager profile; documented update workflow

Outcome: backed up, observable, recoverable. Validate: restore drill, forced-failure ntfy, probe reports DNS down when powered off.

### M3 — Security hardening

- BIOS: Secure Boot Mode → Customized → Reset to Setup Mode
- `sbctl create-keys` + `enroll-keys -m`; `limine.secureBoot.enable`; enable Secure Boot; re-enroll TPM against PCR 0+2+7

Outcome: signed boot, cmdline-injection closed, auto-unlock surviving updates. Validate: `sbctl status` signed, tampered cmdline fails to boot, auto-unlock after a kernel update, re-enroll restores it after a deliberate PCR change.

### M4 — Expansion (later)

- gaming laptop host (`hosts/laptop`, desktop modules)
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

The dendritic pattern (every file a flake-parts module, aspect-oriented across classes, auto-imported with `import-tree`) is purpose-built for sharing across host classes. Not chosen because it is a generic framework built before the second host exists (against a non-goal), adds a large novel concept atop the Home Manager learning goal, and reduces legibility via auto-import and aspect scattering — and legibility matters most for recovery.

Decision: **flake-parts with explicit role modules.** Revisit if host count grows enough that aspect-oriented sharing outweighs the legibility loss; explicit role modules keep that path open.

### Bootloader and Secure Boot: Limine vs lanzaboote

lanzaboote was the initial assumption. Limine was chosen: in-tree, CI-tested nixpkgs module with no external flake input, suiting an appliance tracking `nixos-unstable` for low maintenance — and nixpkgs dropped the `lanzaboote-tool` package in 2025 for lack of integration maintenance, with lanzaboote able to lag systemd on unstable. lanzaboote's edge is its audited single signed UKI, but Limine's module force-enables the safe settings under Secure Boot, so the configuration-correctness gap is small.

Revisit if Limine's Secure Boot integration regresses or a future host clearly needs the signed-UKI model; the phased approach keeps Phase 1 bootloader-agnostic.
