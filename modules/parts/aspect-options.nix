# flake-parts does not know that our dendritic aspect namespace should merge.
# Declare it once so every aspect file can add flake.modules.nixos.<name> or
# flake.modules.homeManager.<name> without fighting over one unique output.
{ lib, ... }:
{
  options.flake.modules = {
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
