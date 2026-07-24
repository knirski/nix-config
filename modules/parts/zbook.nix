# flake-parts module: assembles nixosConfigurations.zbook
{ config, inputs, ... }:
let
  # zbook enables aspects.homeManager.desktop (bitwarden-desktop, a Linux
  # host), so unlike soyo (nixos.base's other consumer, headless/no
  # desktop aspect) it needs the reviewed insecure-package exceptions. See
  # lib/insecure-package-exceptions.nix for what/why, and
  # lib/mk-nixpkgs-args.nix for why this is added here rather than baked
  # into the shared nixos.base aspect soyo also imports.
  insecurePackageExceptions = import ../../lib/insecure-package-exceptions.nix;
in
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
                config.aspects.homeManager.development
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
          system.stateVersion = "26.11";
          nixpkgs = {
            hostPlatform = "x86_64-linux";
            overlays = [
              (_: prev: {
                dgop = inputs.dgop.packages.${prev.stdenv.hostPlatform.system}.default;
              })
            ];
            # Separate `nixpkgs.config` definition from aspects.nixos.base's
            # `nixpkgs.config = sharedNixpkgsArgs.config;` -- disjoint keys
            # (base never sets permittedInsecurePackages when called with no
            # args), so the module system's merge is unambiguous regardless
            # of definition order. Soyo, the other nixos.base consumer, does
            # not add this and so gets none of it.
            config.permittedInsecurePackages = map (e: e.package) insecurePackageExceptions;
          };

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
            # Workstation-only: gh/command-code/development tooling. Declared
            # here (not in the shared aspects.nixos.users aspect) so soyo
            # never gets this secret rekeyed for it. See docs/secrets.md.
            github-token = {
              rekeyFile = ../../secrets/github-token.age;
              owner = "krzysiek";
              group = "users";
              mode = "0400";
            };
          };
        }
      ];
  };
}
