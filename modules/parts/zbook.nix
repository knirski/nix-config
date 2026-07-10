# flake-parts module: assembles nixosConfigurations.zbook
{ config, inputs, ... }:
{
  flake.nixosConfigurations.zbook = inputs.nixpkgs-unstable.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; };
    modules =
      (with config.aspects.nixos; [
        base
        ssh
        tailscale
        desktop
        hyprland
        nvidia
        laptop
        gaming
        workstation
        users
        persistence
        maintenance
        backup
      ])
      ++ [
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
              config.aspects.homeManager.hyprland
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
          system.stateVersion = "26.11";

          # Maintenance: enable for this host, set disk to zbook's NVMe
          lanAppliance.services.maintenance = {
            enable = true;
            smartdDevices = [
              "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2N11292JQEJC"
            ];
          };

          # NVIDIA Optimus: Intel for desktop, NVIDIA on-demand for games
          lanAppliance.services.nvidia = {
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

          age.secrets = {
            tailscale-auth-key = {
              rekeyFile = ../../secrets/tailscale-auth-key-zbook.age;
            };
            zbook-restic-password = {
              rekeyFile = ../../secrets/zbook-restic-password.age;
            };
          };
        }
      ];
  };
}
