# NixOS base aspect — role-neutral defaults shared by every NixOS host.
# Timezone, locale, nix settings, basic packages. Does not select a network
# backend, swap policy, or graphical environment (see host-role-invariants).
_:
let
  sharedNixpkgsArgs = import ../../lib/mk-nixpkgs-args.nix { };
in
{
  aspects.nixos.base =
    { pkgs, ... }:
    {
      time.timeZone = "Europe/Warsaw";
      i18n.defaultLocale = "en_US.UTF-8";
      console.keyMap = "pl2";
      # Fast keyboard repeat on the TTY console (applies to all hosts).
      # Wayland compositors (Sway) set their own repeat rate, but the console
      # defaults to a sluggish 250 ms delay / 10 Hz — these boot params fix that.
      # keyboard.delay=0 → 250 ms; keyboard.rate is in chars/sec.
      boot.kernelParams = [
        "keyboard.delay=0"
        "keyboard.rate=50"
      ];
      environment.variables.EDITOR = "nvim";

      # Shared nixpkgs config (allowUnfree, permittedInsecurePackages, overlays)
      # sourced from lib/mk-nixpkgs-args.nix — single source of truth.
      nixpkgs.config = sharedNixpkgsArgs.config;
      nixpkgs.overlays = sharedNixpkgsArgs.overlays;

      nix.settings = {
        # Pull pre-built closures from the public project cache before building
        # locally. CI already publishes successful main-branch builds there.
        substituters = [
          "https://knirski-nix-config.cachix.org"
        ];
        trusted-public-keys = [
          "knirski-nix-config.cachix.org-1:PZGqi8FqCamG8Pna7PdDIoUKFSYmwR15cjyqlgfZEAk="
        ];
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        # auto-optimise-store = true is intentionally absent.
        # It makes garbage collection O(n) on store size and causes lock
        # contention on every nix command.  Instead, a weekly systemd timer
        # runs `nix store optimise` when the system is idle.
        # Docs: https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-store-optimise
        warn-dirty = false;
        # trusted-users: required for `nixos-rebuild --target-host` to work.
        # Without this, the remote nix daemon rejects unsigned store paths
        # (from `nix-copy-closure`) when the build adds new packages.
        # Include root, the admin user, and @wheel so any future admin works too.
        trusted-users = [
          "root"
          "krzysiek"
          "@wheel"
        ];
      };

      # Weekly nix store optimisation (replaces `auto-optimise-store`, which
      # causes lock contention on every nix command and O(n) GC cost).
      systemd = {
        # Have NixOS render `script`, `preStart`, `postStart`, and related unit
        # fragments through writeShellApplication. This catches undefined
        # variables and ShellCheck findings while the system closure builds.
        # Arbitrary ExecStart commands and separately authored scripts are
        # covered by the repository shell-boundary check instead.
        enableStrictShellChecks = true;
        services.nix-store-optimise = {
          description = "Optimise the Nix store";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.nix}/bin/nix store optimise";
            MemoryMax = "512M";
            CPUQuota = "50%";
            Nice = 19;
            IOSchedulingClass = "idle";
          };
        };
        # nixpkgs also declares an unactivated `nix-optimise.service` for its
        # `nix.optimise` option. This repository deliberately uses the bounded
        # weekly unit above, so remove the redundant manual unit.
        services.nix-optimise.enable = false;
        timers.nix-store-optimise = {
          description = "Weekly Nix store optimisation";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "weekly";
            RandomizedDelaySec = "6h";
            Persistent = true;
          };
        };
      };

      documentation.nixos.enable = true;

      programs = {
        neovim = {
          enable = true;
          viAlias = true;
        };
        zsh.enable = true;
        nh.enable = true;
      };

      environment.systemPackages = with pkgs; [
        git
        htop
        jq
        just
        nix-index # nix-locate: find which package provides a missing command
        nix-output-monitor # nom: real-time nixos-rebuild progress with ETA
        sbctl
      ];
    };
}
