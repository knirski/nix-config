{ ... }: {
  imports = [
    ./nixos/base.nix
    ./nixos/server.nix
    ./nixos/users.nix
    ./nixos/persistence.nix
    ./nixos/blocky.nix
    ./nixos/dhcp.nix
    ./nixos/remote-unlock.nix
    ./nixos/maintenance.nix
    ./nixos/backup.nix
    ./nixos/observability.nix
    ./home/base.nix
    ./parts/perSystem.nix
    ./parts/soyo.nix
    ./parts/aspect-options.nix
    ./parts/topology.nix
  ];
}
