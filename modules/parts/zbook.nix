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
        logitech
        sway
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
        inputs.dms.nixosModules.dank-material-shell
        inputs.dank-greeter.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = ".hm-backup";
            users.krzysiek = {
              imports = [
                config.aspects.homeManager.base
                config.aspects.homeManager.desktop
                config.aspects.homeManager.ssh
                config.aspects.homeManager.sway
                config.aspects.homeManager.kanshi
                ../../hosts/zbook/kanshi.nix
                inputs.dms.homeModules.dank-material-shell
                inputs.dcal.homeModules.dank-calendar
                inputs.dsearch.homeModules.default
                inputs.dms-plugins.homeModules.dms-plugin-registry
              ];
              home = {
                stateVersion = "26.11";
                enableNixpkgsReleaseCheck = false;
              };
            };
          };
        }
        ../../hosts/zbook/users.nix
        ../../hosts/zbook/disko.nix
        ../../hosts/zbook/boot.nix
        ../../hosts/zbook/persistence.nix
        ../../hosts/zbook/backup.nix
        ../../hosts/zbook/networking.nix
        ../../hosts/zbook/topology.nix
        ../../hosts/zbook/maintenance.nix
        ../../hosts/zbook/nvidia.nix
        inputs.nix-topology.nixosModules.default
        inputs.nixos-facter-modules.nixosModules.facter
        { facter.reportPath = ../../hosts/zbook/facter.json; }
        {
          networking.hostName = "zbook";
          nixpkgs.hostPlatform = "x86_64-linux";
          system.stateVersion = "26.11";
          nixpkgs.overlays = [
            (_: prev: {
              dgop = inputs.dgop.packages.${prev.stdenv.hostPlatform.system}.default;
            })
          ];

          age.rekey = {
            hostPubkey = ../../secrets/zbook.pub;
            # Shared operator-side symlink; see docs/secrets.md.  Keep this an
            # absolute string so the private key never enters the Nix store.
            masterIdentities = [
              "/etc/agenix-rekey/master-identity"
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
