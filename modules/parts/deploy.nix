# flake-parts module: sets up deploy-rs for multi-host orchestration.
# Adds deploy.nodes for soyo and zbook, and deploy checks to nix flake check.
{ inputs, ... }:
let
  inherit (inputs) deploy-rs;
  zbookSystem = deploy-rs.lib.x86_64-linux.activate.nixos inputs.self.nixosConfigurations.zbook;
  zbookNode = hostname: {
    inherit hostname;
    sshUser = "krzysiek";
    autoRollback = true;
    magicRollback = true;
    profiles.system = {
      user = "root";
      path = zbookSystem;
    };
  };
in
{
  flake = {
    deploy = {
      nodes = {
        soyo = {
          hostname = "soyo";
          sshUser = "krzysiek";
          autoRollback = true;
          magicRollback = true;
          profiles.system = {
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos inputs.self.nixosConfigurations.soyo;
          };
        };

        zbook = zbookNode "zbook";
        # Keep the normal Tailscale target above and provide an explicit local alias
        # for running deploy-rs directly on the workstation.
        zbook-local = zbookNode "localhost";
      };
    };
  };

  perSystem = { system, ... }: {
    checks = deploy-rs.lib.${system}.deployChecks inputs.self.deploy;
  };
}
