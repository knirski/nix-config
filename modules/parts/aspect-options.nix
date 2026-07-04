# Dendritic aspect namespace. Every aspect module contributes to
# aspects.nixos.<name> and/or aspects.homeManager.<name>, and the host
# assembler toggles them by name. Not under `flake.*` to avoid triggering
# `nix flake check` warnings about non-standard flake outputs.
{ lib, ... }:
{
  options.aspects = {
    nixos = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.raw;
      default = { };
      description = "Reusable NixOS aspect modules assembled by hosts.";
    };

    homeManager = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.raw;
      default = { };
      description = "Reusable Home Manager aspect modules assembled by hosts.";
    };
  };
}
