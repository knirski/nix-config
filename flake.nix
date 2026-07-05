{
  description = "Multi-host NixOS flake; first host is the Soyo DNS/DHCP appliance";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/714a5f8c4ead";

    flake-parts.url = "github:hercules-ci/flake-parts";
    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    preservation.url = "github:nix-community/preservation";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix-rekey.url = "github:oddlama/agenix-rekey";
    agenix-rekey.inputs.nixpkgs.follows = "nixpkgs";

    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    nix-topology.url = "github:oddlama/nix-topology";
    nix-topology.inputs.nixpkgs.follows = "nixpkgs";
  };

  # The whole flake is built by importing `modules/default.nix`, which lists
  # every module file explicitly (the dendritic pattern).
  # `deploy-rs` is intentionally absent until M4.
  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } { imports = [ ./modules ]; };
}
