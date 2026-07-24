# flake-parts module: assembles darwinConfigurations.macbook
# Professional workstation laptop (Apple Silicon).
{ config, inputs, ... }:
let
  # macbook enables aspects.homeManager.desktop like zbook/ubuntu. In
  # practice bitwarden-desktop (the electron_39 consumer -- see
  # lib/insecure-package-exceptions.nix) is guarded to Linux only in
  # modules/home/desktop.nix, so this is currently inert on Darwin, but
  # it's wired in for consistency with the other two hosts sharing the
  # desktop aspect and to avoid silently breaking if that guard ever
  # changes.
  insecurePackageExceptions = import ../../lib/insecure-package-exceptions.nix;
in
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
              config.aspects.homeManager.development
              config.aspects.homeManager.desktop
              config.aspects.homeManager.ssh
              config.aspects.homeManager.aerospace
            ];
            users.krzysiek.home = {
              stateVersion = "26.11";
            };
          };
        }
        ../../hosts/macbook/users.nix
        {
          networking.hostName = "macbook";
          system.stateVersion = 6;
          system.primaryUser = "krzysiek";
          nixpkgs = {
            hostPlatform = "aarch64-darwin";
            # Separate `nixpkgs.config` definition from aspects.darwin.base's
            # `nixpkgs.config = sharedNixpkgsArgs.config;` -- see the matching
            # comment in modules/parts/zbook.nix for why disjoint keys make
            # this merge order-independent.
            config.permittedInsecurePackages = map (e: e.package) insecurePackageExceptions;
          };

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
