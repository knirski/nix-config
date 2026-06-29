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
        blocky
        dhcp
      ])
      ++ [
        inputs.disko.nixosModules.disko
        inputs.agenix.nixosModules.default
        inputs.agenix-rekey.nixosModules.default
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
        ../../hosts/soyo/dns.nix
        ../../hosts/soyo/dhcp.nix
        inputs.nixos-facter-modules.nixosModules.facter
        { facter.reportPath = ../../hosts/soyo/facter.json; }
        ../../hosts/soyo/networking.nix
        {
          networking.hostName = "soyo";
          system.stateVersion = "26.05";

          # Secrets use the agenix-rekey rekeyFile flow (see docs/secrets.md).
          # Master-encrypted files (secrets/*.age) are rekeyed per host via
          # `agenix rekey` into secrets/rekeyed/<host>/.  The default hostPubkey
          # is a dummy placeholder so the first deploy can happen before the
          # real host key is known — set it once soyo.age.pub exists.
          age.rekey = {
            masterIdentities = [ ../../secrets/krzysiek.age.pub ];
            storageMode = "local";
            localStorageDir = ../../. + "/secrets/rekeyed/soyo";
          };
        }
      ];
  };
}
