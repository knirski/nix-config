# flake-parts module: assembles nixosConfigurations.soyo by toggling aspects
# (config.flake.modules.nixos.*) and importing host-specific files.
# Grown incrementally across the following tasks.
{ config, inputs, ... }:
{
  flake.nixosConfigurations.soyo = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; };
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
        inputs.nixos-facter-modules.nixosModules.facter
        { facter.reportPath = ../../hosts/soyo/facter.json; }
        ../../hosts/soyo/networking.nix
        {
          # Temporary scaffold so the early host evaluates under `nix flake check`.
          # Task 4 replaces this with the real disko + Limine boot path.
          boot.loader.grub.enable = false;
          fileSystems."/".device = "none";
          fileSystems."/".fsType = "tmpfs";

          networking.hostName = "soyo";
          system.stateVersion = "26.05";
        }
      ];
  };
}
