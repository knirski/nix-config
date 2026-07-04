# flake-parts module: dev shell, formatter, and repo checks.
{ inputs, ... }: {
  systems = [ "x86_64-linux" ];
  imports = [
    inputs.treefmt-nix.flakeModule
  ];

  perSystem =
    {
      pkgs,
      config,
      system,
      ...
    }:
    {
      treefmt.config = {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
      };
      formatter = config.treefmt.build.wrapper;
      checks.formatting = config.treefmt.build.check inputs.self;

      devShells.default = pkgs.mkShell {
        packages = [
          pkgs.deadnix
          pkgs.gh
          pkgs.git
          pkgs.nh
          pkgs.nixos-anywhere
          pkgs.nixos-facter
          pkgs.nixos-rebuild
          pkgs.sbctl
          inputs.agenix-rekey.packages.${system}.default
        ];
      };
    };
}
