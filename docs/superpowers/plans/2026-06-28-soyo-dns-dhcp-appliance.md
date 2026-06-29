# Soyo DNS/DHCP Appliance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first real host in this flake: `soyo`, a DNS and DHCP appliance built as a dendritic flake, with an impermanent root (blank-snapshot rollback + `preservation`), declarative hardware via `nixos-facter`, that serves the LAN from declarative config and recovers unattended after power loss.

**Architecture:** Dendritic flake. `flake.nix` is thin; `import-tree ./modules` auto-imports every file under `modules/` as a flake-parts module. Reusable behavior lives in *aspect* modules that contribute to `flake.modules.nixos.<aspect>` (and `flake.modules.homeManager.<aspect>`). The host is assembled by a flake-parts module (`modules/parts/soyo.nix`) that toggles aspects via `config.flake.modules.nixos.*` and imports host-specific hardware/data from `hosts/soyo/`. Implement M1 then M2 so the appliance is bootable, state-complete across reboot, recoverable, and observable before adding M3 Secure Boot hardening.

**Tech Stack:** Nix flakes, `flake-parts`, `import-tree` (dendritic), `nixos-facter`, NixOS modules, Home Manager, `disko`, `preservation`, `agenix` (+ optional `agenix-rekey` operator tooling), Blocky, dnsmasq, Prometheus `node_exporter`, Prometheus dnsmasq exporter, Limine, `systemd-networkd`, systemd initrd, `systemd-cryptenroll`, `restic`, `btrbk`, `treefmt-nix`, `deadnix`. Native `nixos-rebuild --target-host` is the day-2 deploy path; `deploy-rs` is deferred to M4 (multi-host).

## Global Constraints

Every task's requirements implicitly include these (exact values, copied from the spec):

- `nixpkgs` tracks `nixos-unstable`; `system.stateVersion = "26.05"`; `home.stateVersion = "26.05"`.
- Kernel uses `pkgs.linuxPackages_latest` with the in-tree `dwmac_motorcomm` NIC driver — no pin, no out-of-tree module. (nixpkgs 26.05's default kernel config lacks the driver, hence `linuxPackages_latest`.)
- Host name `soyo`; static LAN IP `10.0.0.9/24`; gateway `10.0.0.1`; DHCP pool `10.0.0.50,10.0.0.199`; direct-link rescue `192.168.254.2/30` (laptop `192.168.254.1/30`); search/local domain `home.arpa`; wired interface `enp1s0`; disk `/dev/disk/by-id/ata-PELADN_512GB_20250522100164`.
- Dendritic: aspects expose `flake.modules.nixos.<aspect>` / `flake.modules.homeManager.<aspect>`; hosts assemble with `config.flake.modules.nixos.*`. No manual sibling `imports` of aspect files.
- Impermanent root via Btrfs blank-snapshot rollback (systemd initrd) + `preservation`; durable state only under `/persist`. Persisted-path completeness is correctness, not cleanup.
- Hardware via `nixos-facter` (committed `hosts/soyo/facter.json`); no `hardware-configuration.nix`.
- Backups use `restic` via `services.restic.backups` (first-class module) — not rustic/kopia.
- Secrets use plain `agenix` with `age.secrets.<name>.file`. Do not use `agenix-rekey`'s `rekeyFile` flow in M1/M2.
- DNS/DHCP/exporters/initrd-SSH are LAN-interface only, never WAN-facing.
- Learning-oriented, beginner-friendly docs are a first-class deliverable (Task 8), not a by-product.

---

## File Structure

**Reuse (already in the repo as committed host data):**
- `hosts/soyo/reservations.nix` — single source of truth `{ name; mac; ip; }` list (plaintext; MAC/IP are not secrets).
- `hosts/soyo/dns.nix` — existing full Blocky policy; only its outer wrapper is adapted to the shared aspect option (body preserved verbatim).

**Create — dendritic flake-parts modules (auto-imported by `import-tree ./modules`):**
- `flake.nix` — thin: inputs + `import-tree ./modules`.
- `modules/parts/perSystem.nix` — `systems`, `treefmt`, formatter, `checks.formatting`, dev shell.
- `modules/parts/soyo.nix` — the host assembler: `flake.nixosConfigurations.soyo`.
- `modules/nixos/base.nix` — `flake.modules.nixos.base` (role-neutral defaults).
- `modules/nixos/server.nix` — `flake.modules.nixos.server` (networkd, sshd policy).
- `modules/nixos/users.nix` — `flake.modules.nixos.users` (user policy + agenix secret inventory).
- `modules/nixos/persistence.nix` — `flake.modules.nixos.persistence` (preservation + blank-snapshot rollback + agenix identity path).
- `modules/nixos/remote-unlock.nix` — `flake.modules.nixos.remote-unlock` (initrd SSH + network).
- `modules/nixos/blocky.nix` — `flake.modules.nixos.blocky` (DNS; full settings passthrough).
- `modules/nixos/dhcp.nix` — `flake.modules.nixos.dhcp` (dnsmasq DHCP + options).
- `modules/nixos/backup.nix` — `flake.modules.nixos.backup` (restic + btrbk).
- `modules/nixos/maintenance.nix` — `flake.modules.nixos.maintenance` (gc, scrub, smartd, free-space, ntfy).
- `modules/nixos/observability.nix` — `flake.modules.nixos.observability` (node + dnsmasq exporters).
- `modules/home/base.nix` — `flake.modules.homeManager.base` (headless HM profile).

**Create — host-specific hardware/data (plain Nix, imported by the assembler):**
- `hosts/soyo/facter.json` — `nixos-facter` report.
- `hosts/soyo/boot.nix` — kernel pin, NIC module, Limine, systemd initrd, TPM crypttab, zram.
- `hosts/soyo/disko.nix` — GPT, EFI, LUKS2, Btrfs `root`/`nix`/`persist`/`snapshots` subvolumes.
- `hosts/soyo/networking.nix` — static LAN address + firewall.
- `hosts/soyo/initrd-unlock.nix` — Phase-1 remote-unlock host wiring.
- `hosts/soyo/persistence.nix` — Soyo persisted-path inventory (`preservation.preserveAt."/persist"`).
- `hosts/soyo/dhcp.nix` — DHCP ranges, router/DNS options, reservations.
- `hosts/soyo/users.nix` — `root`/`krzysiek` user assembly + password secrets.
- `hosts/soyo/backup.nix` — backup paths, Synology target, ntfy topic.
- `hosts/soyo/observability.nix` — exporter bindings.

**Create — secrets, docs, scripts:**
- `secrets/{krzysiek.age.pub,soyo.age.pub,krzysiek-authorized-key.pub,secrets.nix}`
- `docs/learning/README.md` — beginner-friendly guided reading path + glossary (first-class deliverable).
- `docs/{install-soyo.md,update-and-rollback.md,recovery.md,backup-and-restore.md,validation-checklist.md}`
- `scripts/rebuild-soyo`, `scripts/deploy-soyo` (native `nixos-rebuild`).

---

## Task 1: Scaffold the thin dendritic flake and top-level checks

**Files:**
- Create: `flake.nix`
- Create: `modules/parts/perSystem.nix`
- Create: `modules/parts/soyo.nix`

**Produces:** `nixosConfigurations.soyo` (minimal), `devShells.x86_64-linux.default`, `formatter.x86_64-linux`, `checks.x86_64-linux.formatting`. The dendritic backbone: `import-tree ./modules` and the `flake.modules.nixos.*` namespace later aspects extend.

- [ ] **Step 1: Prove the repo is not yet a flake**

Run: `nix flake show`
Expected: FAIL with an error that `flake.nix` is missing in the repo root.

- [ ] **Step 2: Create the thin `flake.nix`**

```nix
{
  description = "Multi-host NixOS flake; first host is the Soyo DNS/DHCP appliance";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    preservation.url = "github:nix-community/preservation";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix-rekey.url = "github:oddlama/agenix-rekey";
    agenix-rekey.inputs.nixpkgs.follows = "nixpkgs";

    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  # The whole flake is built by auto-importing every module file under ./modules
  # (the dendritic pattern). `deploy-rs` is intentionally absent until M4.
  outputs =
    inputs@{ flake-parts, import-tree, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (import-tree ./modules);
}
```

- [ ] **Step 3: Create the per-system flake-parts module**

```nix
# modules/parts/perSystem.nix
# flake-parts module: dev shell, formatter, and repo checks.
{ inputs, ... }:
{
  systems = [ "x86_64-linux" ];
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem =
    { pkgs, config, system, ... }:
    {
      treefmt.config = {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
      };
      formatter = config.treefmt.build.wrapper;
      checks.formatting = config.treefmt.build.check inputs.self;

      devShells.default = pkgs.mkShell {
        packages = [
          pkgs.deadnix
          pkgs.git
          pkgs.nh
          pkgs.nixos-anywhere
          pkgs.nixos-facter
          inputs.agenix.packages.${system}.default
          inputs.agenix-rekey.packages.${system}.default
        ];
      };
    };
}
```

- [ ] **Step 4: Create the minimal host assembler**

```nix
# modules/parts/soyo.nix
# flake-parts module: assembles nixosConfigurations.soyo by toggling aspects
# (config.flake.modules.nixos.*) and importing host-specific files.
# Grown incrementally across the following tasks.
{ config, inputs, ... }:
{
  flake.nixosConfigurations.soyo = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; };
    modules = [
      {
        networking.hostName = "soyo";
        system.stateVersion = "26.05";
      }
    ];
  };
}
```

- [ ] **Step 5: Lock inputs and verify the flake shape**

Run: `nix flake lock`
Expected: PASS and `flake.lock` is created with the declared inputs.

Run: `nix flake show`
Expected: PASS and `nixosConfigurations.soyo`, `devShells.x86_64-linux.default`, and `formatter.x86_64-linux` are listed.

Run: `nix eval .#nixosConfigurations.soyo.config.networking.hostName`
Expected: PASS with `"soyo"`.

- [ ] **Step 6: Run the formatting check**

Run: `nix flake check`
Expected: PASS for `formatting`.

- [ ] **Step 7: Commit the scaffold**

```bash
git add flake.nix flake.lock modules/parts
git commit -m "feat: scaffold thin dendritic flake for soyo"
```

## Task 2: Add base/server/users aspects and the headless Home Manager profile

**Files:**
- Create: `modules/nixos/base.nix`
- Create: `modules/nixos/server.nix`
- Create: `modules/nixos/users.nix`
- Create: `modules/home/base.nix`
- Create: `hosts/soyo/users.nix`
- Modify: `modules/parts/soyo.nix`

**Interfaces:**
- Produces: `flake.modules.nixos.{base,server,users}`, `flake.modules.homeManager.base`. The assembler turns these on and wires Home Manager.

- [ ] **Step 1: Verify the base aspect is not yet present**

Run: `test -f modules/nixos/base.nix`
Expected: FAIL with exit status `1`.

- [ ] **Step 2: Create the role-neutral base aspect**

```nix
# modules/nixos/base.nix
{
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      time.timeZone = "Europe/Warsaw";
      i18n.defaultLocale = "en_US.UTF-8";

      nix.settings = {
        experimental-features = [ "nix-command" "flakes" ];
        auto-optimise-store = true;
        warn-dirty = false;
      };

      documentation.nixos.enable = true;

      environment.systemPackages = with pkgs; [
        git
        htop
        jq
        vim
      ];
    };
}
```

- [ ] **Step 3: Create the server, users, and Home Manager aspects**

```nix
# modules/nixos/server.nix
{
  flake.modules.nixos.server = {
    networking.useNetworkd = true;
    systemd.network.enable = true;

    services.openssh.enable = true;
    services.openssh.settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
}
```

```nix
# modules/nixos/users.nix
# User *policy* only. Per-user definitions and password secrets are host data
# (hosts/soyo/users.nix); the agenix secret inventory is added in Task 6.
{
  flake.modules.nixos.users = {
    users.mutableUsers = false;

    security.sudo = {
      enable = true;
      wheelNeedsPassword = true;
    };
  };
}
```

```nix
# modules/home/base.nix
{
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      home.stateVersion = "26.05";

      programs.bash.enable = true;
      programs.git.enable = true;
      programs.home-manager.enable = true;

      home.packages = with pkgs; [
        fd
        ripgrep
        tmux
      ];
    };
}
```

- [ ] **Step 4: Create the host user assembly (key auth now, password secrets in Task 6)**

```nix
# hosts/soyo/users.nix
{
  users.users.krzysiek = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../../secrets/krzysiek-authorized-key.pub)
    ];
  };
}
```

For this task, create a placeholder authorized key so the build evaluates; replace it with the real key in Task 6:

```bash
mkdir -p secrets
ssh-keygen -t ed25519 -N "" -f /tmp/soyo-placeholder -C placeholder
cp /tmp/soyo-placeholder.pub secrets/krzysiek-authorized-key.pub
```

- [ ] **Step 5: Wire the aspects and Home Manager into the assembler**

Replace the `modules = [ … ];` list in `modules/parts/soyo.nix`:

```nix
modules =
  (with config.flake.modules.nixos; [
    base
    server
    users
  ])
  ++ [
    inputs.home-manager.nixosModules.home-manager
    (
      { ... }:
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.krzysiek.imports = [ config.flake.modules.homeManager.base ];
      }
    )
    ../../hosts/soyo/users.nix
    {
      networking.hostName = "soyo";
      system.stateVersion = "26.05";
    }
  ];
```

- [ ] **Step 6: Evaluate the shared defaults**

Run: `nix eval .#nixosConfigurations.soyo.config.services.openssh.enable`
Expected: PASS with `true`.

Run: `nix eval .#nixosConfigurations.soyo.config.users.mutableUsers`
Expected: PASS with `false`.

Run: `nix eval .#nixosConfigurations.soyo.config.home-manager.useGlobalPkgs`
Expected: PASS with `true`.

- [ ] **Step 7: Commit the shared base**

```bash
git add modules/nixos modules/home modules/parts/soyo.nix hosts/soyo/users.nix secrets/krzysiek-authorized-key.pub
git commit -m "feat: add base, server, users, and home-manager aspects"
```

## Task 3: Add declarative hardware (nixos-facter) and static networking

**Files:**
- Create: `hosts/soyo/facter.json`
- Create: `hosts/soyo/networking.nix`
- Modify: `modules/parts/soyo.nix`

**Interfaces:**
- Consumes: `inputs.nixos-facter-modules.nixosModules.facter`, option `facter.reportPath`.

- [ ] **Step 1: Confirm the host still has no hardware report wired**

Run: `nix eval .#nixosConfigurations.soyo.config.networking.hostName`
Expected: PASS with `"soyo"` (host still evaluates without hardware facts).

- [ ] **Step 2: Generate and commit the `nixos-facter` report from the target or rehearsal VM**

Run on the target/VM (in the dev shell, which provides `nixos-facter`):

```bash
sudo nixos-facter -o hosts/soyo/facter.json
```

Expected: PASS and `hosts/soyo/facter.json` contains the detected hardware (disk, NIC, TPM). For an early VM rehearsal before real hardware, `nixos-anywhere --generate-hardware-config nixos-facter ./hosts/soyo/facter.json …` produces the same file.

- [ ] **Step 3: Create the host networking file (static LAN address outside the DHCP pool)**

```nix
# hosts/soyo/networking.nix
{
  networking.useDHCP = false;

  systemd.network.networks."10-enp1s0" = {
    matchConfig.Name = "enp1s0";
    address = [ "10.0.0.9/24" ];
    routes = [ { Gateway = "10.0.0.1"; } ];
    networkConfig = {
      DNS = "127.0.0.1";
      Domains = [ "home.arpa" ];
    };
  };

  networking.firewall.enable = true;
}
```

- [ ] **Step 4: Wire facter and networking into the assembler**

Add to the `++ [ … ]` list in `modules/parts/soyo.nix` (before the inline hostName module):

```nix
inputs.nixos-facter-modules.nixosModules.facter
{ facter.reportPath = ../../hosts/soyo/facter.json; }
../../hosts/soyo/networking.nix
```

- [ ] **Step 5: Verify host identity, hardware, and interface wiring**

Run: `nix eval .#nixosConfigurations.soyo.config.facter.reportPath`
Expected: PASS and the path ends with `hosts/soyo/facter.json`.

Run: `nix eval .#nixosConfigurations.soyo.config.systemd.network.networks.\"10-enp1s0\".address`
Expected: PASS with `["10.0.0.9/24"]`.

- [ ] **Step 6: Commit host assembly**

```bash
git add hosts/soyo/facter.json hosts/soyo/networking.nix modules/parts/soyo.nix
git commit -m "feat: add nixos-facter hardware and static networking"
```

## Task 4: Add disk layout, impermanent root (preservation + rollback), kernel/Limine, and Phase 1 unlock

**Files:**
- Create: `hosts/soyo/disko.nix`
- Create: `hosts/soyo/boot.nix`
- Create: `modules/nixos/persistence.nix`
- Create: `hosts/soyo/persistence.nix`
- Create: `modules/nixos/remote-unlock.nix`
- Create: `hosts/soyo/initrd-unlock.nix`
- Modify: `modules/parts/soyo.nix`

**Interfaces:**
- Consumes: `inputs.disko.nixosModules.disko`, `inputs.preservation.nixosModules.preservation`.
- Produces: `flake.modules.nixos.{persistence,remote-unlock}`. LUKS mapper name is `crypted`; root subvolume is `root`, blank snapshot is `root-blank`.

- [ ] **Step 1: Show the M1 boot features are still absent**

Run: `nix eval .#nixosConfigurations.soyo.config.boot.loader.limine.enable`
Expected: PASS with `false`.

Run: `nix eval .#nixosConfigurations.soyo.config.boot.initrd.systemd.services.rollback-root.serviceConfig.Type`
Expected: FAIL (the rollback unit does not exist yet).

- [ ] **Step 2: Create the `disko` layout with EFI, LUKS2, and Btrfs subvolumes (incl. `root`)**

```nix
# hosts/soyo/disko.nix
# `root` is wiped to a blank snapshot every boot (see modules/nixos/persistence.nix);
# only /nix and /persist (plus snapshots) hold durable state.
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/ata-PELADN_512GB_20250522100164";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
        luks = {
          size = "100%";
          label = "luks";
          content = {
            type = "luks";
            name = "crypted";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "/root" = {
                  mountpoint = "/";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                "/nix" = {
                  mountpoint = "/nix";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                "/persist" = {
                  mountpoint = "/persist";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                "/snapshots" = {
                  mountpoint = "/snapshots";
                  mountOptions = [ "compress=zstd" ];
                };
              };
            };
          };
        };
      };
    };
  };
}
```

- [ ] **Step 3: Create the boot file (linuxPackages_latest, in-tree driver, Limine, TPM-ready systemd initrd, zram)**

```nix
# hosts/soyo/boot.nix
{ config, pkgs, ... }:
{
  boot.kernelPackages = pkgs.linuxPackages_latest;

  zramSwap.enable = true;
  security.tpm2.enable = true;

  boot.loader.limine.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;
  boot.initrd.availableKernelModules = [ "tpm_crb" "nvme" "xhci_pci" "uas" "sd_mod" ];

  # Phase 1 TPM auto-unlock; passphrase keyslot stays as the break-glass fallback.
  boot.initrd.luks.devices.crypted = {
    device = "/dev/disk/by-partlabel/luks";
    allowDiscards = true;
    crypttabExtraOpts = [ "tpm2-device=auto" ];
  };
}
```

- [ ] **Step 4: Create the persistence aspect (preservation + blank-snapshot rollback + agenix identity)**

```nix
# modules/nixos/persistence.nix
{ inputs, ... }:
{
  flake.modules.nixos.persistence =
    { pkgs, ... }:
    {
      imports = [ inputs.preservation.nixosModules.preservation ];

      preservation.enable = true;

      # /persist must be mounted before stage-2 activation so agenix can read the
      # host key from its durable location (see age.identityPaths below).
      fileSystems."/persist".neededForBoot = true;

      # agenix decrypts using the durable host key, not the wiped /etc/ssh.
      age.identityPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

      # Erase-your-darlings on Btrfs: restore `root` from a blank snapshot each
      # boot. Ordered after the LUKS device opens and before the root is mounted.
      # Nested subvolumes (systemd/services create them under /var/lib) must be
      # deleted first or `btrfs subvolume delete root` fails.
      boot.initrd.systemd.services.rollback-root = {
        wantedBy = [ "initrd.target" ];
        after = [ "systemd-cryptsetup@crypted.service" ];
        before = [ "sysroot.mount" ];
        unitConfig.DefaultDependencies = "no";
        serviceConfig.Type = "oneshot";
        script = ''
          set -euo pipefail
          mkdir -p /mnt
          mount -o subvol=/ /dev/mapper/crypted /mnt

          # Canonical bootstrap: root-blank is the readonly empty snapshot taken
          # ONCE at install (see docs/install-soyo.md). Guard before destroying
          # root so a missing blank fails loud with root intact, not a brick.
          if [ ! -e /mnt/root-blank ]; then
            echo "rollback-root: /root-blank missing — create it at install:" >&2
            echo "  btrfs subvolume snapshot -r /mnt/root /mnt/root-blank" >&2
            umount /mnt
            exit 1
          fi

          # Delete nested subvolumes under the live root first (systemd/services
          # create them under /var/lib), or `btrfs subvolume delete root` fails.
          ${pkgs.btrfs-progs}/bin/btrfs subvolume list -o /mnt/root \
            | ${pkgs.coreutils}/bin/cut -f9 -d' ' \
            | while read -r sub; do
                ${pkgs.btrfs-progs}/bin/btrfs subvolume delete "/mnt/$sub"
              done

          ${pkgs.btrfs-progs}/bin/btrfs subvolume delete /mnt/root
          ${pkgs.btrfs-progs}/bin/btrfs subvolume snapshot /mnt/root-blank /mnt/root
          umount /mnt
        '';
      };
    };
}
```

- [ ] **Step 5: Declare Soyo's persisted-path inventory**

```nix
# hosts/soyo/persistence.nix
# We deliberately do NOT persist /etc/{passwd,shadow,group,...}: with
# users.mutableUsers = false and hashedPasswordFile, NixOS regenerates them
# declaratively each boot from the agenix secrets. /var/lib/nixos is persisted
# so declarative UID/GID assignments stay stable.
{
  preservation.preserveAt."/persist" = {
    directories = [
      { directory = "/var/lib/nixos"; inInitrd = true; }
      { directory = "/etc/ssh"; inInitrd = true; }
      "/var/lib/dnsmasq"
      "/var/log"
    ];
    files = [
      { file = "/etc/machine-id"; inInitrd = true; }
    ];
    users.krzysiek = {
      directories = [
        { directory = ".ssh"; mode = "0700"; }
        ".local/share/direnv"
      ];
      files = [ ".bash_history" ];
    };
  };
}
```

- [ ] **Step 6: Create the remote-unlock aspect and the host-local Phase 1 wiring**

```nix
# modules/nixos/remote-unlock.nix
{
  flake.modules.nixos.remote-unlock =
    { lib, config, ... }:
    let
      cfg = config.lanAppliance.services.remoteUnlock;
    in
    {
      options.lanAppliance.services.remoteUnlock = {
        enable = lib.mkEnableOption "systemd-initrd remote unlock";
        interface = lib.mkOption { type = lib.types.str; };
        lanAddress = lib.mkOption { type = lib.types.str; };
        rescueAddress = lib.mkOption { type = lib.types.str; };
        sshHostKeys = lib.mkOption { type = lib.types.listOf lib.types.str; };
      };

      config = lib.mkIf cfg.enable {
        boot.initrd.network.enable = true;
        boot.initrd.network.ssh = {
          enable = true;
          port = 2222;
          hostKeys = cfg.sshHostKeys;
        };
        # The initrd SSH host key lives unencrypted on the ESP (it must be
        # available before LUKS unlock); keep a stable fingerprint across rebuilds.
        systemd.tmpfiles.rules = [ "d /boot/initrd-ssh 0700 root root -" ];

        boot.initrd.network.networks."10-${cfg.interface}" = {
          matchConfig.Name = cfg.interface;
          address = [ cfg.lanAddress cfg.rescueAddress ];
          routes = [ { Gateway = "10.0.0.1"; } ];
        };
      };
    };
}
```

```nix
# hosts/soyo/initrd-unlock.nix
{
  lanAppliance.services.remoteUnlock = {
    enable = true;
    interface = "enp1s0";
    lanAddress = "10.0.0.9/24";
    rescueAddress = "192.168.254.2/30";
    sshHostKeys = [ "/boot/initrd-ssh/ssh_host_ed25519_key" ];
  };
}
```

The referenced key must exist on the ESP before the first activation that enables
remote unlock, or `nixos-rebuild switch` fails copying it into the initrd. The ESP
(`/boot`, vfat) is outside the encrypted container and is not wiped by the root
rollback, so a key placed there has a stable fingerprint across rebuilds. Generate
it once on the target during install (also captured in `docs/install-soyo.md`):

```bash
install -d -m 700 /boot/initrd-ssh
ssh-keygen -t ed25519 -N "" -f /boot/initrd-ssh/ssh_host_ed25519_key
```

This key authenticates only the pre-unlock initrd SSH endpoint; it is distinct
from the stage-2 `/persist/etc/ssh` host key.

- [ ] **Step 7: Wire the disk/boot/persistence/unlock pieces into the assembler**

Add the new aspects to the `with config.flake.modules.nixos; [ … ]` list:

```nix
(with config.flake.modules.nixos; [
  base
  server
  users
  persistence
  remote-unlock
])
```

Add the disko module and host files to the `++ [ … ]` list:

```nix
inputs.disko.nixosModules.disko
../../hosts/soyo/disko.nix
../../hosts/soyo/boot.nix
../../hosts/soyo/persistence.nix
../../hosts/soyo/initrd-unlock.nix
```

- [ ] **Step 8: Verify evaluation and the M1 boot path**

Run: `nix eval .#nixosConfigurations.soyo.config.boot.kernelPackages.kernel.modDirVersion`
Expected: PASS and the value begins with `7`.

Run: `nix eval .#nixosConfigurations.soyo.config.fileSystems.\"/persist\".neededForBoot`
Expected: PASS with `true`.

Run: `nix eval .#nixosConfigurations.soyo.config.boot.initrd.luks.devices.crypted.crypttabExtraOpts`
Expected: PASS with `["tpm2-device=auto"]`.

Run: `nix eval .#nixosConfigurations.soyo.config.age.identityPaths`
Expected: PASS with `[ "/persist/etc/ssh/ssh_host_ed25519_key" ]` (it is a list; do not use `--raw`).

Run: `nix eval .#nixosConfigurations.soyo.config.boot.initrd.systemd.services.rollback-root.serviceConfig.Type`
Expected: PASS with `"oneshot"`.

Run: `nix build .#nixosConfigurations.soyo.config.system.build.diskoScript`
Expected: PASS and a disko script is built from the declared layout.

- [ ] **Step 9: Commit the bootable M1 foundation**

```bash
git add modules/nixos/persistence.nix modules/nixos/remote-unlock.nix hosts/soyo/disko.nix hosts/soyo/boot.nix hosts/soyo/persistence.nix hosts/soyo/initrd-unlock.nix modules/parts/soyo.nix
git commit -m "feat: add disk layout, impermanent root, and phase-1 boot path"
```

## Task 5: Implement Blocky, dnsmasq DHCP, and reservation-driven LAN naming

**Files:**
- Create: `modules/nixos/blocky.nix`
- Create: `modules/nixos/dhcp.nix`
- Create: `hosts/soyo/dhcp.nix`
- Modify: `hosts/soyo/dns.nix`
- Modify: `modules/parts/soyo.nix`

**Interfaces:**
- Produces: `flake.modules.nixos.{blocky,dhcp}`; options `lanAppliance.services.blocky.{enable,lanInterface,settings}` and `lanAppliance.services.dhcp.{enable,interface,routerAddress,dnsServer,searchDomain,leaseFile,dhcpRanges,reservations}`.

- [ ] **Step 1: Prove DNS and DHCP are not wired yet**

Run: `nix eval .#nixosConfigurations.soyo.config.services.blocky.enable`
Expected: return `false`.

Run: `nix eval .#nixosConfigurations.soyo.config.services.dnsmasq.enable`
Expected: return `false`.

- [ ] **Step 2: Create the Blocky aspect (full settings passthrough — keeps the rich host policy)**

```nix
# modules/nixos/blocky.nix
{
  flake.modules.nixos.blocky =
    { lib, config, ... }:
    let
      cfg = config.lanAppliance.services.blocky;
    in
    {
      options.lanAppliance.services.blocky = {
        enable = lib.mkEnableOption "Blocky DNS";
        lanInterface = lib.mkOption { type = lib.types.str; };
        # Full Blocky settings come from host data so the appliance's real
        # upstreams/bootstrapDns/blocklists/customDNS are preserved verbatim.
        settings = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };
      };

      config = lib.mkIf cfg.enable {
        services.blocky = {
          enable = true;
          settings = cfg.settings;
        };

        services.resolved.enable = false;
        networking.firewall.allowedTCPPorts = [ 53 ];
        networking.firewall.allowedUDPPorts = [ 53 ];
        networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ 4000 ];
      };
    };
}
```

- [ ] **Step 3: Create the dnsmasq DHCP aspect (with router/DNS/search options)**

```nix
# modules/nixos/dhcp.nix
{
  flake.modules.nixos.dhcp =
    { lib, config, ... }:
    let
      cfg = config.lanAppliance.services.dhcp;
      leaseDir = builtins.dirOf cfg.leaseFile;
      reservationLines = map (r: "${r.mac},${r.ip},${r.name},infinite") cfg.reservations;
    in
    {
      options.lanAppliance.services.dhcp = {
        enable = lib.mkEnableOption "dnsmasq DHCP";
        interface = lib.mkOption { type = lib.types.str; };
        routerAddress = lib.mkOption { type = lib.types.str; };
        dnsServer = lib.mkOption { type = lib.types.str; };
        searchDomain = lib.mkOption { type = lib.types.str; };
        leaseFile = lib.mkOption { type = lib.types.str; };
        dhcpRanges = lib.mkOption { type = lib.types.listOf lib.types.str; };
        reservations = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption { type = lib.types.str; };
                mac = lib.mkOption { type = lib.types.str; };
                ip = lib.mkOption { type = lib.types.str; };
              };
            }
          );
        };
      };

      config = lib.mkIf cfg.enable {
        services.dnsmasq = {
          enable = true;
          resolveLocalQueries = false;
          settings = {
            port = 5353; # Blocky owns :53; dnsmasq serves local reverse on 5353.
            interface = cfg.interface;
            "bind-interfaces" = true;
            "dhcp-authoritative" = true;
            "dhcp-range" = cfg.dhcpRanges;
            "dhcp-host" = reservationLines;
            "dhcp-option" = [
              "option:router,${cfg.routerAddress}"
              "option:dns-server,${cfg.dnsServer}"
              "option:domain-search,${cfg.searchDomain}"
            ];
            "dhcp-fqdn" = true;
            "dhcp-leasefile" = cfg.leaseFile;
            domain = cfg.searchDomain;
            local = "/${cfg.searchDomain}/";
            "expand-hosts" = true;
            "domain-needed" = true;
            "bogus-priv" = true;
            "local-service" = true;
          };
        };

        # Lease DB lives on /persist so leases survive reboots/rebuilds.
        systemd.tmpfiles.rules = [
          "d ${leaseDir} 0750 dnsmasq dnsmasq -"
        ];

        networking.firewall.allowedUDPPorts = [ 67 ];
      };
    };
}
```

- [ ] **Step 4: Add the host-local DHCP policy**

```nix
# hosts/soyo/dhcp.nix
let
  reservations = import ./reservations.nix;
in
{
  lanAppliance.services.dhcp = {
    enable = true;
    interface = "enp1s0";
    routerAddress = "10.0.0.1";
    dnsServer = "10.0.0.9";
    searchDomain = "home.arpa";
    leaseFile = "/var/lib/dnsmasq/dnsmasq.leases";
    reservations = reservations;
    dhcpRanges = [ "10.0.0.50,10.0.0.199,12h" ];
  };
}
```

- [ ] **Step 5: Re-wrap the existing Blocky policy behind the aspect option (preserve the body)**

`hosts/soyo/dns.nix` already holds the full Blocky policy under `services.blocky = { enable = true; settings = { … }; }`. Change only the outer wrapper; keep the `settings` body (upstreams, `bootstrapDns`, `customDNS` mappings, conditional routing, blocklists, allowlists, caching) byte-for-byte:

```diff
-{ lib, ... }:
-...
-  services.blocky = {
-    enable = true;
-    settings = {
+{ lib, ... }:
+...
+  lanAppliance.services.blocky = {
+    enable = true;
+    lanInterface = "enp1s0";
+    settings = {
        ports = {
          dns = [
            "127.0.0.1:53"
            "10.0.0.9:53"
          ];
          http = "10.0.0.9:4000";
        };
       # ... keep upstreams, bootstrapDns, customDNS, conditional, blocking, caching unchanged ...
     };
   };
-
-  services.resolved.enable = false;
-  networking.firewall.allowedUDPPorts = [ 53 ];
-  networking.firewall.allowedTCPPorts = [ 53 ];
-  networking.firewall.interfaces.enp1s0.allowedTCPPorts = [ 4000 ];
```

The deleted `services.resolved`/firewall lines are now provided by the aspect. Keep `hosts/soyo/reservations.nix` as committed plaintext data — do not move MAC/IP into secrets.

- [ ] **Step 6: Wire the DNS/DHCP aspects and host files into the assembler**

Add to the `with config.flake.modules.nixos; [ … ]` list: `blocky` and `dhcp`. Add to the `++ [ … ]` list:

```nix
../../hosts/soyo/dns.nix
../../hosts/soyo/dhcp.nix
```

- [ ] **Step 7: Verify naming and DHCP options**

Run: `nix eval .#nixosConfigurations.soyo.config.services.blocky.settings.customDNS.mapping.\"soyo.home.arpa\"`
Expected: PASS with `"10.0.0.9"`.

Run: `nix eval .#nixosConfigurations.soyo.config.services.dnsmasq.settings.\"dhcp-option\"`
Expected: PASS and the list contains `option:router,10.0.0.1`, `option:dns-server,10.0.0.9`, and `option:domain-search,home.arpa`.

Run: `nix eval .#nixosConfigurations.soyo.config.services.dnsmasq.settings.\"dhcp-leasefile\"`
Expected: PASS with `"/var/lib/dnsmasq/dnsmasq.leases"`.

- [ ] **Step 8: Build the host and commit DNS/DHCP**

Run: `nix build .#nixosConfigurations.soyo.config.system.build.toplevel`
Expected: PASS and the closure contains Blocky and dnsmasq.

```bash
git add modules/nixos/blocky.nix modules/nixos/dhcp.nix hosts/soyo/dhcp.nix hosts/soyo/dns.nix modules/parts/soyo.nix
git commit -m "feat: add soyo dns and dhcp aspects"
```

## Task 6: Add agenix secrets and complete the operator account policy

**Files:**
- Create: `secrets/krzysiek.age.pub`
- Create: `secrets/soyo.age.pub`
- Create: `secrets/krzysiek-authorized-key.pub` (replace the Task 2 placeholder)
- Create: `secrets/secrets.nix`
- Modify: `modules/nixos/users.nix`
- Modify: `hosts/soyo/users.nix`

**Interfaces:**
- Consumes: `config.age.secrets.{root-password,krzysiek-password,restic-password,ntfy-token}.path`. The agenix identity is `/persist/etc/ssh/ssh_host_ed25519_key` (set in Task 4).

- [x] **Step 1: Show the agenix inventory is missing**
- [x] **Step 2: Create the agenix recipient map**
- [x] **Step 3: Add the secret inventory to the users aspect**
- [x] **Step 4: Wire the password secrets into the host user definitions**
- [x] **Step 5: Generate the recipient inventory and encrypt the payloads (plain agenix)**
- [x] **Step 6: Verify the secrets evaluate**
- [x] **Step 7: Commit the secret wiring**

```bash
git add secrets modules/nixos/users.nix hosts/soyo/users.nix
git commit -m "feat: add agenix-managed operator secrets"
```

## Task 7: Add backup, maintenance, and observability aspects (M2 cut-line)

**Files:**
- Create: `modules/nixos/backup.nix`
- Create: `modules/nixos/maintenance.nix`
- Create: `modules/nixos/observability.nix`
- Create: `hosts/soyo/backup.nix`
- Create: `hosts/soyo/observability.nix`
- Modify: `modules/parts/soyo.nix`

**Interfaces:**
- Consumes: `config.age.secrets.{restic-password,ntfy-token}.path`.
- Produces: `flake.modules.nixos.{backup,maintenance,observability}`; options `lanAppliance.services.backup.*`, `lanAppliance.services.maintenance.{ntfyTopicUrl,ntfyTokenFile}`, `lanAppliance.services.observability.*`. The shared `ntfy-notify@` template and `OnFailure` wiring live in the maintenance aspect.

- [ ] **Step 1: Prove the operational services do not exist yet**

Run: `nix eval .#nixosConfigurations.soyo.config.services.restic.backups`
Expected: return an empty attribute set `{ }`.

- [ ] **Step 2: Create the backup aspect (restic via the first-class module + btrbk)**

```nix
# modules/nixos/backup.nix
{
  flake.modules.nixos.backup =
    { lib, config, ... }:
    let
      cfg = config.lanAppliance.services.backup;
    in
    {
      options.lanAppliance.services.backup = {
        enable = lib.mkEnableOption "restic and btrbk backups";
        paths = lib.mkOption { type = lib.types.listOf lib.types.str; };
        repository = lib.mkOption { type = lib.types.str; };
      };

      config = lib.mkIf cfg.enable {
        services.btrbk.instances.local = {
          onCalendar = "hourly";
          settings.volume."/persist".subvolume."/snapshots" = { };
        };

        services.restic.backups.soyo = {
          repository = cfg.repository;
          initialize = true;
          paths = cfg.paths;
          passwordFile = config.age.secrets.restic-password.path;
          timerConfig.OnCalendar = "daily";
          pruneOpts = [
            "--keep-daily 7"
            "--keep-weekly 4"
            "--keep-monthly 6"
          ];
        };

        systemd.services.restic-backups-soyo.unitConfig.OnFailure = [
          "ntfy-notify@restic-backups-soyo.service"
        ];
      };
    };
}
```

- [ ] **Step 3: Create the maintenance aspect (gc, scrub, smartd, free-space, ntfy)**

```nix
# modules/nixos/maintenance.nix
{
  flake.modules.nixos.maintenance =
    { pkgs, lib, config, ... }:
    let
      cfg = config.lanAppliance.services.maintenance;
    in
    {
      options.lanAppliance.services.maintenance = {
        ntfyTopicUrl = lib.mkOption { type = lib.types.str; };
        ntfyTokenFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
        };
      };

      config = {
        nix.gc = {
          automatic = true;
          dates = "weekly";
          options = "--delete-older-than 14d";
        };

        boot.loader.limine.maxGenerations = 10;

        services.btrfs.autoScrub = {
          enable = true;
          interval = "monthly";
          fileSystems = [ "/persist" ];
        };
        services.fstrim.enable = true;
        services.timesyncd.enable = true;
        services.smartd = {
          enable = true;
          notifications.wall.enable = false;
          notifications.x11.enable = false;
          notifications.mail.enable = false;
          defaults.monitored = "-a -o on -S on -s (S/../.././02|L/../../7/04)";
        };

        services.journald.extraConfig = ''
          SystemMaxUse=512M
        '';

        # Proactive free-space alert at 85% of /persist allocation.
        systemd.services.soyo-free-space-check = {
          serviceConfig.Type = "oneshot";
          script = ''
            set -euo pipefail
            stats="$(${pkgs.btrfs-progs}/bin/btrfs filesystem usage --raw /persist)"
            size="$(printf '%s\n' "$stats" | ${pkgs.gawk}/bin/awk '/Device size:/ { print $3 }')"
            allocated="$(printf '%s\n' "$stats" | ${pkgs.gawk}/bin/awk '/Device allocated:/ { print $3 }')"
            [ -n "$size" ] && [ -n "$allocated" ]
            if [ "$allocated" -ge $(( size * 85 / 100 )) ]; then
              exit 1
            fi
          '';
          unitConfig.OnFailure = [ "ntfy-notify@soyo-free-space-check.service" ];
        };
        systemd.timers.soyo-free-space-check = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "hourly";
            Persistent = true;
          };
        };

        # Shared failure-notifier template; the unit name is the %i instance.
        systemd.services."ntfy-notify@" = {
          serviceConfig.Type = "oneshot";
          script = ''
            set -euo pipefail
            auth=()
            ${lib.optionalString (cfg.ntfyTokenFile != null) ''
              auth=( -H "Authorization: Bearer $(${pkgs.coreutils}/bin/cat ${cfg.ntfyTokenFile})" )
            ''}
            ${pkgs.curl}/bin/curl -fsS "''${auth[@]}" \
              -d "unit %i failed on soyo" \
              "${cfg.ntfyTopicUrl}"
          '';
        };

        # OnFailure -> ntfy for the scheduled maintenance units.
        systemd.services.nix-gc.unitConfig.OnFailure = [ "ntfy-notify@nix-gc.service" ];
        systemd.services."btrfs-scrub-persist".unitConfig.OnFailure = [
          "ntfy-notify@btrfs-scrub-persist.service"
        ];
      };
    };
}
```

- [ ] **Step 4: Create the observability aspect and host policy**

```nix
# modules/nixos/observability.nix
{
  flake.modules.nixos.observability =
    { lib, config, ... }:
    let
      cfg = config.lanAppliance.services.observability;
    in
    {
      options.lanAppliance.services.observability = {
        enable = lib.mkEnableOption "lightweight metrics exporters";
        interface = lib.mkOption { type = lib.types.str; };
        listenAddress = lib.mkOption {
          type = lib.types.str;
          default = "10.0.0.9";
        };
      };

      config = lib.mkIf cfg.enable {
        services.prometheus.exporters.node = {
          enable = true;
          listenAddress = cfg.listenAddress;
          enabledCollectors = [ "systemd" ];
        };

        services.prometheus.exporters.dnsmasq = {
          enable = true;
          listenAddress = cfg.listenAddress;
          dnsmasqListenAddress = "127.0.0.1:5353";
          leasesPath = "/var/lib/dnsmasq/dnsmasq.leases";
        };

        # Scrape/storage/dashboards stay off-box (Grafana Alloy / Prometheus on the NAS).
        networking.firewall.interfaces.${cfg.interface}.allowedTCPPorts = [
          9100
          9153
        ];
      };
    };
}
```

```nix
# hosts/soyo/backup.nix
{ config, ... }:
{
  lanAppliance.services.backup = {
    enable = true;
    repository = "sftp:backup@10.0.0.10:/volume1/restic/soyo";
    paths = [ "/persist" ];
  };

  lanAppliance.services.maintenance.ntfyTopicUrl = "https://ntfy.sh/soyo-lan";
  lanAppliance.services.maintenance.ntfyTokenFile = config.age.secrets.ntfy-token.path;
}
```

```nix
# hosts/soyo/observability.nix
{
  lanAppliance.services.observability = {
    enable = true;
    interface = "enp1s0";
    listenAddress = "10.0.0.9";
  };
}
```

- [ ] **Step 5: Wire the M2 aspects into the assembler**

Add to the `with config.flake.modules.nixos; [ … ]` list: `backup`, `maintenance`, `observability`. Add to the `++ [ … ]` list:

```nix
../../hosts/soyo/backup.nix
../../hosts/soyo/observability.nix
```

- [ ] **Step 6: Verify M2 services**

Run: `nix eval .#nixosConfigurations.soyo.config.services.restic.backups.soyo.initialize`
Expected: PASS with `true`.

Run: `nix eval .#nixosConfigurations.soyo.config.services.btrfs.autoScrub.enable`
Expected: PASS with `true`.

Run: `nix eval .#nixosConfigurations.soyo.config.boot.loader.limine.maxGenerations`
Expected: PASS with `10`.

Run: `nix eval .#nixosConfigurations.soyo.config.systemd.services.\"ntfy-notify@\".serviceConfig.Type`
Expected: PASS with `"oneshot"`.

Run: `nix eval .#nixosConfigurations.soyo.config.services.prometheus.exporters.dnsmasq.leasesPath`
Expected: PASS with `"/var/lib/dnsmasq/dnsmasq.leases"`.

Run: `nix eval .#nixosConfigurations.soyo.config.networking.firewall.interfaces.enp1s0.allowedTCPPorts`
Expected: PASS and the list contains `4000`, `9100`, and `9153`.

- [ ] **Step 7: Build and commit the M2 operational baseline**

Run: `nix build .#nixosConfigurations.soyo.config.system.build.toplevel`
Expected: PASS with backup, maintenance, and exporter units present.

```bash
git add modules/nixos/backup.nix modules/nixos/maintenance.nix modules/nixos/observability.nix hosts/soyo/backup.nix hosts/soyo/observability.nix modules/parts/soyo.nix
git commit -m "feat: add backup, maintenance, and observability aspects"
```

## Task 8: Write operator + beginner-friendly docs and native deploy/rebuild helpers

**Files:**
- Create: `docs/learning/README.md`
- Create: `docs/install-soyo.md`
- Create: `docs/update-and-rollback.md`
- Create: `docs/recovery.md`
- Create: `docs/backup-and-restore.md`
- Create: `docs/validation-checklist.md`
- Create: `scripts/rebuild-soyo`
- Create: `scripts/deploy-soyo`

- [ ] **Step 1: Verify the docs are still missing**

Run: `test -f docs/learning/README.md`
Expected: FAIL with exit status `1`.

- [ ] **Step 2: Write the beginner-friendly guided learning doc (first-class deliverable)**

Create `docs/learning/README.md` with: a design-journey narrative that builds the design up from basics, a reading order mapped to the M1–M4 roadmap, a glossary, and per-concept notes. Use this skeleton (fill each section with a plain-language "what it is / why we use it here" paragraph plus a canonical link):

```md
# Learning Path: the Soyo flake from zero

## Design journey: how we got here (read this first)
Start from the simplest thing that could work and add each decision as a step,
showing what was tried, what was rejected, and *why* — so a beginner sees the
design as a sequence of choices, not a finished monolith. Cover, in order:
1. "Just a NixOS config" -> why a flake, then why flake-parts (modular outputs).
2. Explicit role-module imports -> why we pivoted to the dendritic pattern
   (`import-tree`, `flake.modules.nixos.*`): the radical-modern learning goal,
   and the legibility cost we accept and mitigate with docs.
3. A normal mutable root -> why impermanence; then tmpfs-root vs the
   Btrfs blank-snapshot rollback we chose, and why `preservation` over the
   older `impermanence` module (maturity argument consciously overridden).
4. Hardware: `nixos-generate-config` -> why the declarative `nixos-facter` report.
5. Backups: why `restic` won over `rustic`/`kopia` — the first-class NixOS module
   (`services.restic.backups`) outweighs a "nicer" hand-wired tool. State the
   general principle this taught us.
6. Deploy: why native `nixos-rebuild --target-host` now and `deploy-rs` deferred to M4.
7. DNS/DHCP: why Blocky + dnsmasq over AdGuard Home (declarative purity, DHCP depth).
8. Boot/Secure Boot: why Limine over lanzaboote (in-tree module, no extra input).
Each step links to the matching "Appendix: Alternatives Considered" entry in the spec.

## How to read this repo (in order)
1. Flakes & `flake.nix` — https://nix.dev/concepts/flakes
2. flake-parts + the dendritic pattern (`import-tree`, `flake.modules.nixos.*`) — https://flake.parts
3. The module system & options — https://nixos.org/manual/nixos/stable/#sec-writing-modules
4. `hosts/soyo` assembly: which aspects are turned on and where they come from
5. disko & the disk layout — search.nixos.org
6. Impermanence: blank-snapshot rollback + `preservation`
7. agenix secrets (+ the `/persist` host-key ordering)
8. TPM2 auto-unlock, Limine, Secure Boot (M3)

## Glossary
flake-parts · aspect module · dendritic · import-tree · impermanence ·
subvolume · blank-snapshot rollback · preservation · PCR · keyslot · DoH ·
reservation · `flake.modules.nixos.<aspect>`

## Aspect -> host wiring (the dendritic indirection, explained)
- Every file under `modules/` is auto-imported by `import-tree`.
- An aspect file sets `flake.modules.nixos.<name> = { ... };`.
- `modules/parts/soyo.nix` builds the host by listing those aspect names
  (`with config.flake.modules.nixos; [ base server ... ]`) plus host files.
- To answer "what does soyo run?", read `modules/parts/soyo.nix`.
```

The success test: a reader new to Nix can follow the design journey and the reading order and understand both *what* the appliance does and *why each modern choice was made* — including the alternatives that were rejected along the way.

- [ ] **Step 3: Write the install and recovery runbooks**

Create `docs/install-soyo.md`. Cover: USB path; Wi-Fi/USB-Ethernet caveat; `nixos-facter` report; `disko`; then the two one-time bootstrap steps that the running system depends on, in this exact order:

```bash
# (a) Root-blank. disko mounts the `root` subvolume at /mnt (per-mountpoint), so
# /mnt IS the root subvol and /mnt/root does NOT exist. To create root-blank as a
# SIBLING of root, mount the Btrfs top-level (subvolid 5) — the same `subvol=/`
# view the initrd rollback unit uses — while root is still EMPTY:
mkdir -p /mnt-top
mount -o subvol=/ /dev/mapper/crypted /mnt-top
btrfs subvolume snapshot -r /mnt-top/root /mnt-top/root-blank   # canonical empty blank
umount /mnt-top

# (b) Initrd break-glass SSH host key on the ESP (survives the root rollback;
# stable fingerprint). /mnt/boot is the ESP mounted by disko:
install -d -m 700 /mnt/boot/initrd-ssh
ssh-keygen -t ed25519 -N "" -f /mnt/boot/initrd-ssh/ssh_host_ed25519_key

# (c) Stage-2 host key, PRE-PLACED on /persist so agenix can decrypt on the very
# first boot. This is what breaks the bootstrap circularity: the config's
# hashedPasswordFile -> agenix -> age.identityPaths = /persist/etc/ssh/... key.
# preservation bind-mounts /persist/etc/ssh -> /etc/ssh, so sshd reuses this key
# (does not regenerate it) and the fingerprint is stable.
install -d -m 700 /mnt/persist/etc/ssh
ssh-keygen -t ed25519 -N "" -f /mnt/persist/etc/ssh/ssh_host_ed25519_key
```

Now the agenix recipient is known **before** install. In the **same installer environment on the target** (USB-local provisioning fetched the flake here, and the dev shell provides `ssh-to-age`/`agenix`), enroll Soyo's recipient and re-encrypt the secrets to it — this is the `ssh-to-age` of Soyo's pubkey from step (c):

```bash
# In the installer shell, inside the fetched repo checkout. /mnt/persist is the
# target's persist subvolume mounted by disko.
ssh-to-age < /mnt/persist/etc/ssh/ssh_host_ed25519_key.pub > secrets/soyo.age.pub
# re-encrypt every secret to [operator, soyo] (Task 6), then commit/push so the
# enrolled recipient is captured in git history:
agenix -r   # rekey all secrets to the recipients in secrets/secrets.nix
git add secrets && git commit -m "feat: enroll soyo agenix recipient"
```

(If you instead provision from a separate workstation via `nixos-anywhere`, copy `ssh_host_ed25519_key.pub` out of the target first, then run the same `ssh-to-age`/`agenix -r` there.)

Only then run `nixos-install` from the flake — activation decrypts the password secrets on the first boot, so the appliance comes up fully usable (root/krzysiek passwords set), not in a degraded no-password state. Reboot; reservation verification before DHCP cutover.

Alternative — "bootstrap then finalize" (when agenix material is not available at install time): skip step (c) and the enrollment above, `nixos-install` as-is. agenix can't decrypt yet, so it soft-fails: the password secrets are absent and console/root password login is unavailable, but `krzysiek` SSH **key** auth still works (its `authorizedKeys` is committed plaintext, not a secret). First boot generates the `/persist` host key; then enroll `secrets/soyo.age.pub` from it, re-encrypt, and `./scripts/deploy-soyo switch` — the redeploy populates the passwords. Use this only if one-pass enrollment isn't possible.

Use this skeleton:

```md
# Soyo Install
## Prerequisites
## USB Provisioning
## First Boot
## DHCP Cutover
## Post-Install Validation
```

Create `docs/recovery.md` with: TPM auto-unlock expectations; local console unlock; LAN initrd SSH unlock (port 2222); direct-link rescue using `192.168.254.1/30` on the laptop and `192.168.254.2/30` on Soyo; router-DHCP re-enable fallback.

- [ ] **Step 4: Write update/backup/validation docs and the helpers (native nixos-rebuild)**

Create `docs/update-and-rollback.md`:

```md
# Update and Rollback
1. `nix flake update nixpkgs`
2. `nix flake check`
3. `./scripts/deploy-soyo test`     # build locally, copy closure, activate remotely (no boot default)
4. `./scripts/deploy-soyo switch`   # build locally, copy closure, activate + set boot default
5. `sudo nixos-rebuild switch --rollback --flake .#soyo` if the new generation is bad
# deploy-rs is deferred to M4 (multi-host); single-host uses native nixos-rebuild.
```

Create `docs/validation-checklist.md`:

```md
# Validation Checklist
- `nix build .#nixosConfigurations.soyo.config.system.build.toplevel`
- `enp1s0` is present and up on the pinned kernel
- `ssh soyo.home.arpa` resolves from a DHCP client
- Blocky answers on port 53 and blocks a known test domain
- dnsmasq issues leases in `10.0.0.50-10.0.0.199` and clients get router + DNS options
- root is restored from the blank snapshot each boot; the persisted inventory survives reboot
- the agenix host key on /persist decrypts secrets on a clean boot
- `node_exporter`, Blocky metrics, and dnsmasq exporter answer on their ports
- TPM auto-unlock succeeds on a normal reboot
- A forced failed unit emits an ntfy notification
- A restic backup completes and a restore drill succeeds
```

Create `docs/backup-and-restore.md`:

```md
# Backup and Restore
## Data Classes
## Local Snapshots (btrbk)
## Restic to Synology (services.restic.backups)
## Restore Drill
1. `restic snapshots`
2. `restic restore <snapshot-id> --target /tmp/restore-test`
3. Compare the restored test path against the source path
```

Create `scripts/rebuild-soyo` (local):

```bash
#!/usr/bin/env bash
set -euo pipefail
mode="${1:-dry}"
case "$mode" in
  dry)    exec sudo nixos-rebuild dry-run --flake .#soyo ;;
  test)   exec sudo nixos-rebuild test    --flake .#soyo ;;
  switch) exec sudo nixos-rebuild switch  --flake .#soyo ;;
  build)  exec nix build .#nixosConfigurations.soyo.config.system.build.toplevel ;;
  *) echo "usage: $0 {dry|test|switch|build}" >&2; exit 1 ;;
esac
```

Create `scripts/deploy-soyo` (build locally, activate on Soyo via native `--target-host`; no `--build-host`, so the closure is built on the workstation and copied — the N150 never builds). Add `--build-host "$target"` only if you deliberately want Soyo to build:

```bash
#!/usr/bin/env bash
set -euo pipefail
mode="${1:-switch}"
target="krzysiek@10.0.0.9"
case "$mode" in
  test)   exec nixos-rebuild test   --flake .#soyo --target-host "$target" --use-remote-sudo ;;
  boot)   exec nixos-rebuild boot   --flake .#soyo --target-host "$target" --use-remote-sudo ;;
  switch) exec nixos-rebuild switch --flake .#soyo --target-host "$target" --use-remote-sudo ;;
  *) echo "usage: $0 {test|boot|switch}" >&2; exit 1 ;;
esac
```

- [ ] **Step 5: Verify docs and helpers**

Run: `chmod +x scripts/rebuild-soyo scripts/deploy-soyo`
Expected: PASS.

Run: `rg -ni "USB Provisioning|direct-link rescue|aspect -> host|Restore Drill|target-host" docs scripts`
Expected: PASS and the expected headings/modes are found (`-i`: the learning-doc heading is `## Aspect -> host wiring`, so the search must be case-insensitive).

Run: `shellcheck scripts/rebuild-soyo scripts/deploy-soyo`
Expected: PASS if `shellcheck` is available; otherwise run each with its usage arg and confirm it prints a valid command.

- [ ] **Step 6: Commit the operational and learning docs**

```bash
git add docs scripts
git commit -m "docs: add learning path, runbooks, and native deploy helpers"
```

## Task 9: Add M3 Secure Boot hardening and the validation checklist

**Files:**
- Modify: `hosts/soyo/boot.nix`
- Modify: `docs/recovery.md`
- Modify: `docs/validation-checklist.md`

- [ ] **Step 1: Capture the Phase 1 baseline before hardening**

Run: `nix eval .#nixosConfigurations.soyo.config.boot.loader.limine.enable`
Expected: PASS with `true`.

- [ ] **Step 2: Enable Limine Secure Boot**

Add to `hosts/soyo/boot.nix`:

```nix
boot.loader.limine.secureBoot.enable = true;
```

Document the operator sequence in `docs/recovery.md`:

```md
1. Set Secure Boot Mode to Customized.
2. Reset firmware keys to Setup Mode.
3. Run `sbctl create-keys`.
4. Run `sbctl enroll-keys -m`.
5. Enable Secure Boot in firmware.
6. Re-enroll the TPM keyslot against PCR 0+2+7.
```

- [ ] **Step 3: Expand the validation checklist with the hardening checks**

Add to `docs/validation-checklist.md`:

```md
- `sbctl status` reports Secure Boot enabled and signed
- TPM auto-unlock still works after a kernel/initrd update
- A deliberate PCR change forces a passphrase unlock until `systemd-cryptenroll` is re-run
- LAN initrd SSH unlock works
- Direct-link rescue unlock works with the router path down
- A restic restore drill recovers a known test path
```

- [ ] **Step 4: Rebuild and run the full repo gates**

Run: `nix build .#nixosConfigurations.soyo.config.system.build.toplevel`
Expected: PASS.

Run: `nix flake check`
Expected: PASS.

Run: `deadnix .`
Expected: PASS with no unused bindings.

- [ ] **Step 5: Commit the hardened baseline**

```bash
git add hosts/soyo/boot.nix docs/recovery.md docs/validation-checklist.md
git commit -m "feat: harden soyo boot with secure boot plan"
```

## Self-Review

**Spec coverage**
- Dendritic flake (`import-tree`, `flake.modules.nixos.*`, aspect→host assembler): Tasks 1–2, wired through every later task.
- Impermanent root (blank-snapshot rollback + `preservation`), agenix host-key ordering, zstd, zram: Task 4.
- `nixos-facter` hardware: Task 3.
- `linuxPackages_latest` + in-tree `dwmac_motorcomm`, Limine, TPM Phase-1 unlock, remote/direct-link unlock: Tasks 4.
- Blocky (full policy preserved — B1) + dnsmasq DHCP with router/DNS/search options (B2): Task 5.
- agenix secrets, correct relative paths (B3), password hashes: Task 6.
- restic via `services.restic.backups` (not rustic/kopia), btrbk, maintenance (gc, scrub, smartd, free-space, generation limit, generic OnFailure), observability exporters: Task 7.
- Beginner-friendly learning doc + operator runbooks + native `nixos-rebuild` deploy (deploy-rs deferred to M4): Task 8.
- M3 Secure Boot: Task 9.
- Incremental assembler growth so each checkpoint evaluates (B4): Tasks 1→7 each only reference aspects already created.

**Design notes (now codified in the spec, called out here for implementers)**
- The host **assembler** is `modules/parts/soyo.nix` (a flake-parts module — it must read `config.flake.modules.*`); `hosts/soyo/` holds hardware/data only. Home Manager wiring lives in the assembler because it needs `config.flake.modules.homeManager.base`. (Matches spec Repository Structure.)
- `/etc/{passwd,shadow,group,…}` are intentionally **not** persisted: `mutableUsers = false` + `hashedPasswordFile` regenerate them declaratively each boot; only `/var/lib/nixos` is persisted for stable IDs. (Matches spec Impermanence Baseline.)

**Gaps deliberately left out**
- Synology Uptime Kuma probe and off-site NAS replication are documented operator steps, not in-flake.
- BIOS toggles and the final `systemd-cryptenroll` enroll are operator actions in the runbooks.
- M4 (laptop host, `deploy-rs`, future services) is out of scope.

**Placeholder scan**
- No `TODO`/`TBD`. The plan is fully specified for implementation-critical code paths (modules, host data, assembler, checkpoints). Two deliverables are intentionally scaffolded, not literal: Task 5's Blocky migration is a diff-only wrapper change preserving the existing `settings` body verbatim, and Task 8's `docs/learning/README.md` is a guided skeleton the author fills in as prose. Every run step shows expected output. The Task 2 placeholder authorized key is explicitly replaced in Task 6.

**Type consistency**
- One host (`soyo`), one LAN IP (`10.0.0.9`), one rescue IP (`192.168.254.2/30`), one pool (`10.0.0.50-10.0.0.199`), one LUKS mapper (`crypted`), one root/blank pair (`root`/`root-blank`).
- Option namespaces consistent: `lanAppliance.services.{blocky,dhcp,remoteUnlock,backup,maintenance,observability}`; aspect namespace `flake.modules.nixos.<aspect>`.
