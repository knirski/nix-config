# flake-parts module: assembles nixosConfigurations.soyo by toggling aspects
# (config.flake.modules.nixos.*) and importing host-specific files.
# Grown incrementally across the following tasks.
{ inputs, ... }:
{
  flake.nixosConfigurations.soyo = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; };
    modules = [
      {
        # Temporary scaffold so the early host evaluates under `nix flake check`.
        # Task 4 replaces this with the real disko + Limine boot path.
        boot.loader.grub.enable = false;
        fileSystems."/".device = "none";
        fileSystems."/".fsType = "tmpfs";

        networking.hostName = "soyo";
        system.stateVersion = "26.05";
      }
    ];
  };
}
