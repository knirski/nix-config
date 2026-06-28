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
        persistence
        remote-unlock
      ])
      ++ [
        inputs.disko.nixosModules.disko
        inputs.agenix.nixosModules.default
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
        ../../hosts/soyo/disko.nix
        ../../hosts/soyo/boot.nix
        ../../hosts/soyo/persistence.nix
        ../../hosts/soyo/initrd-unlock.nix
        inputs.nixos-facter-modules.nixosModules.facter
        { facter.reportPath = ../../hosts/soyo/facter.json; }
        ../../hosts/soyo/networking.nix
        {
          networking.hostName = "soyo";
          system.stateVersion = "26.05";
        }
      ];
  };
}
