# Darwin base aspect — system-level config mirroring modules/nixos/base.nix.
# Nix settings, timezone, locale, basic packages, macOS defaults.
_:
let
  sharedNixpkgsArgs = import ../../lib/mk-nixpkgs-args.nix { };
in
{
  aspects.darwin.base =
    { pkgs, ... }:
    {
      time.timeZone = "Europe/Warsaw";

      nixpkgs = {
        hostPlatform = "aarch64-darwin";
        # Shared nixpkgs config (allowUnfree, permittedInsecurePackages, overlays)
        # sourced from lib/mk-nixpkgs-args.nix — single source of truth.
        inherit (sharedNixpkgsArgs) config overlays;
      };

      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        substituters = [
          "https://knirski-nix-config.cachix.org"
        ];
        trusted-public-keys = [
          "knirski-nix-config.cachix.org-1:PZGqi8FqCamG8Pna7PdDIoUKFSYmwR15cjyqlgfZEAk="
        ];
        warn-dirty = false;
      };

      # macOS defaults — sensible starting point.
      # Requires system.primaryUser to be set (done in the host assembler).
      system.defaults = {
        dock = {
          autohide = true;
          mru-spaces = false;
        };
        finder = {
          AppleShowAllExtensions = true;
          FXPreferredViewStyle = "Nlsv";
        };
        NSGlobalDomain = {
          AppleShowAllExtensions = true;
          InitialKeyRepeat = 15;
          KeyRepeat = 2;
        };
      };

      programs.zsh.enable = true;

      environment.systemPackages = with pkgs; [
        git
        htop
        jq
        just
        nix-output-monitor
      ];
    };
}
