# flake-parts module: dev shell, formatter, and repo checks.
{ inputs, ... }: {
  systems = [ "x86_64-linux" ];
  imports = [
    inputs.treefmt-nix.flakeModule
    # Registers the `agenix-rekey.rekey` flake app used by `agenix rekey`.
    inputs.agenix-rekey.flakeModule
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
      packages.deadnix = pkgs.deadnix;
      checks.lan-inventory =
        pkgs.runCommand "lan-inventory-test"
          {
            buildInputs = [ pkgs.python3 ];
          }
          ''
            cp ${../../modules/nixos/observability/lan_inventory.py} lan_inventory.py
            cp ${../../modules/nixos/observability/lan_inventory_test.py} lan_inventory_test.py
            python3 -m unittest lan_inventory_test
            touch $out
          '';

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
