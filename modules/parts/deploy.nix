# flake-parts module: sets up deploy-rs for multi-host orchestration.
# Adds deploy.nodes for soyo and zbook, and deploy checks to nix flake check.
{ inputs, ... }:
let
  inherit (inputs) deploy-rs;
in
{
  flake.deploy.nodes.soyo = {
    hostname = "soyo";
    sshUser = "krzysiek";
    autoRollback = true;
    magicRollback = true;
    profiles.system = {
      user = "root";
      path = deploy-rs.lib.x86_64-linux.activate.nixos inputs.self.nixosConfigurations.soyo;
    };
  };

  flake.deploy.nodes.zbook = {
    hostname = "zbook";
    sshUser = "krzysiek";
    autoRollback = true;
    magicRollback = true;
    profiles.system = {
      user = "root";
      path = deploy-rs.lib.x86_64-linux.activate.nixos inputs.self.nixosConfigurations.zbook;
    };
  };

  perSystem = { system, ... }: {
    checks = deploy-rs.lib.${system}.deployChecks inputs.self.deploy;
  };
}
