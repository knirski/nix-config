# flake-parts module: assembles nixosConfigurations.zbook
{ config, inputs, ... }:
{
  flake.nixosConfigurations.zbook = inputs.nixpkgs-unstable.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; };
    modules =
      (with config.aspects.nixos; [
        base
        desktop
        nvidia
        laptop
        gaming
        workstation
        users
        persistence
        maintenance
      ])
      ++ [
        # Overlay cosmic-ext packages from stable (not available in unstable snapshot)
        {
          nixpkgs.overlays = [
            (final: _: {
              cosmic-ext-applet-external-monitor-brightness =
                inputs.nixpkgs.legacyPackages.x86_64-linux.cosmic-ext-applet-external-monitor-brightness;
              cosmic-ext-tweaks = inputs.nixpkgs.legacyPackages.x86_64-linux.cosmic-ext-tweaks;
              cosmic-fan-control = final.callPackage ../../modules/pkgs/cosmic-fan-control { };
            })
          ];
        }
        inputs.disko.nixosModules.disko
        inputs.agenix.nixosModules.default
        inputs.agenix-rekey.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.krzysiek.imports = [
              config.aspects.homeManager.base
              config.aspects.homeManager.desktop
            ];
            users.krzysiek.home.enableNixpkgsReleaseCheck = false;
          };
        }
        ../../hosts/zbook/users.nix
        ../../hosts/zbook/disko.nix
        ../../hosts/zbook/boot.nix
        ../../hosts/zbook/persistence.nix
        ../../hosts/zbook/backup.nix
        ../../hosts/zbook/networking.nix
        ../../hosts/zbook/topology.nix
        inputs.nix-topology.nixosModules.default
        inputs.nixos-facter-modules.nixosModules.facter
        { facter.reportPath = ../../hosts/zbook/facter.json; }
        {
          networking.hostName = "zbook";
          nixpkgs.hostPlatform = "x86_64-linux";
          nixpkgs.config.allowUnfree = true;
          system.stateVersion = "26.05";

          # Maintenance: enable for this host, set disk to zbook's NVMe
          maintenance = {
            enable = true;
            smartdDevices = [
              "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2N11292JQEJC"
            ];
          };

          # NVIDIA Optimus: Intel for desktop, NVIDIA on-demand for games
          workstation.nvidiaConfig = {
            enable = true;
            prime = {
              intelBusId = "PCI:0:2:0";
              nvidiaBusId = "PCI:1:0:0";
            };
            syncMode = "offload";
          };

          age.rekey = {
            hostPubkey = ../../secrets/zbook.pub;
            masterIdentities = [
              "/home/krzysiek/.ssh/soyo_ed25519"
            ];
            storageMode = "local";
            localStorageDir = ../../. + "/secrets/rekeyed/zbook";
          };
        }
      ];
  };
}
