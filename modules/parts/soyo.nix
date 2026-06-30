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
          # hostPubkey reads from secrets/soyo.pub — the raw SSH public key.
          # Go `age` (used by agenix activation) can only decrypt
          # -> ssh-ed25519 recipients with -i ssh_key, not -> X25519.
          # During bootstrap (before host key exists) this must be a dummy
          # SSH public key placeholder; overwrite with the real key from
          # /persist/etc/ssh/ during first install.
          age.rekey = {
            hostPubkey = ../../secrets/soyo.pub;
            # Path to the operator's SSH private key, used to decrypt
            # master-encrypted secrets before rekeying for the host.
            # Must be an absolute string (not a Nix path) so it's NOT
            # copied to the nix store.  Adjust to your machine:
            #   workstation: /home/krzysiek/.ssh/id_ed25519
            #   live ISO:    /home/nixos/.ssh/id_ed25519
            masterIdentities = [
              "/home/krzysiek/.ssh/id_ed25519"
            ];
            storageMode = "local";
            localStorageDir = ../../. + "/secrets/rekeyed/soyo";
          };
        }
      ];
  };
}
