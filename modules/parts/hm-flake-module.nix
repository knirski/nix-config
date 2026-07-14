# Import the home-manager flake-parts module so that `homeConfigurations`
# becomes a valid flake-parts output option. This enables standalone HM
# host assemblers (e.g. modules/parts/ubuntu.nix) to set
# `flake.homeConfigurations.<name>`.
{ inputs, ... }:
{
  imports = [
    inputs.home-manager.flakeModules.home-manager
  ];
}
