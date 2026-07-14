# flake-parts module: assembles darwinConfigurations.macbook
# Professional workstation laptop (Apple Silicon).
{ config, inputs, ... }:
{
  flake.darwinConfigurations.macbook = inputs.nix-darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    specialArgs = { inherit inputs; };
    modules =
      (with config.aspects.darwin; [
        base
      ])
      ++ [
        # TODO: uncomment once secrets are set up for macbook
        # inputs.agenix.darwinModules.default
        # inputs.agenix-rekey.darwinModules.default
        inputs.home-manager.darwinModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.krzysiek.imports = [
              config.aspects.homeManager.base
              config.aspects.homeManager.desktop
              config.aspects.homeManager.ssh
              config.aspects.homeManager.aerospace
            ];
            users.krzysiek.home.enableNixpkgsReleaseCheck = false;
          };
        }
        ../../hosts/macbook/users.nix
        {
          networking.hostName = "macbook";
          nixpkgs.hostPlatform = "aarch64-darwin";
          system.stateVersion = 6;
          system.primaryUser = "krzysiek";

          # TODO: uncomment and create secrets once macbook hardware is available.
          # See plan: ~/.commandcode/plans/add-macbook-nix-darwin.md
          # age.rekey = {
          #   hostPubkey = ../../secrets/macbook.pub;
          #   masterIdentities = [
          #     "/etc/agenix-rekey/master-identity"
          #   ];
          #   storageMode = "local";
          #   localStorageDir = ../../. + "/secrets/rekeyed/macbook";
          # };
          #
          # age.secrets = {
          #   macbook-github-token = {
          #     rekeyFile = ../../secrets/macbook-github-token.age;
          #   };
          # };
        }
      ];
  };
}
