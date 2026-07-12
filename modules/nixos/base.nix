{
  aspects.nixos.base =
    { pkgs, ... }:
    {
      time.timeZone = "Europe/Warsaw";
      i18n.defaultLocale = "en_US.UTF-8";
      environment.variables.EDITOR = "nvim";

      # Allow unfree packages globally. Some packages in the nixpkgs
      # catalogue (e.g. NVIDIA driver, Steam, VS Code, command-code CLI)
      # are unfree by license — declared so by the authors, not by us.
      nixpkgs.config = {
        allowUnfree = true;
        permittedInsecurePackages = [
          "electron-39.8.10"
        ];
      };

      # Make command-code available everywhere (used in home.base).
      # Make command-code available everywhere (used in home.base).
      nixpkgs.overlays = [
        (final: _: {
          command-code = final.callPackage ../../modules/_pkgs/command-code.nix { };
        })
      ];

      nix.settings = {
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
      systemd.services.nix-store-optimise = {
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
      systemd.timers.nix-store-optimise = {
        description = "Weekly Nix store optimisation";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "weekly";
          RandomizedDelaySec = "6h";
          Persistent = true;
        };
      };

      documentation.nixos.enable = true;

      programs = {
        neovim = {
          enable = true;
          viAlias = true;
        };
        zsh.enable = true;
        nh = {
          enable = true;
          clean = {
            enable = true;
            extraArgs = "--keep-since 30d --keep 3";
          };
          flake = "/home/krzysiek/github/knirski/nix-config";
        };
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
