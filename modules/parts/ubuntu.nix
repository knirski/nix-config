# flake-parts module: assembles homeConfigurations.ubuntu
# Professional work laptop (Ubuntu 24.04 LTS, standalone Home Manager).
# No NixOS or nix-darwin — only user environment managed by HM.
{ config, inputs, ... }:
{
  flake.homeConfigurations.ubuntu = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs-unstable (
      (import ../../lib/mk-nixpkgs-args.nix { }) // { system = "x86_64-linux"; }
    );
    modules = [
      config.aspects.homeManager.base
      config.aspects.homeManager.development
      config.aspects.homeManager.desktop
      config.aspects.homeManager.ssh
      config.aspects.homeManager.sway
      inputs.dms.homeModules.dank-material-shell
      inputs.dcal.homeModules.dank-calendar
      inputs.dsearch.homeModules.default
      inputs.dms-plugins.homeModules.dms-plugin-registry
      {
        home = {
          username = "krzysiek";
          homeDirectory = "/home/krzysiek";
          stateVersion = "26.11";
        };
      }
    ];
  };
}
