# flake-parts module: dev shell, formatter, and repo checks.
{ inputs, ... }: {
  systems = [ "x86_64-linux" ];
  imports = [
    inputs.treefmt-nix.flakeModule
    inputs.git-hooks.flakeModule
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
      pre-commit.settings = {
        hooks = {
          treefmt.enable = true;
          deadnix.enable = true;
          statix.enable = true;
          statix.settings.ignore = [
            "modules/nixos/observability.nix"
            "lib/observability/*"
          ];
          typos.enable = true;
          check-merge-conflicts.enable = true;
          end-of-file-fixer.enable = true;
          end-of-file-fixer.excludes = [
            "facter\\.json$"
            "\\.svg$"
          ];
          typos.settings.config = {
            default = {
              "extend-words" = {
                crypted = "crypted";
                facter = "facter";
                HDA = "HDA";
                Hed = "Hed";
                FACTER = "FACTER";
                sxl = "sxl";
              };
            };
          };
        };
      };
      treefmt.config = {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
      };
      formatter = config.treefmt.build.wrapper;
      checks.formatting = config.treefmt.build.check inputs.self;
      packages.deadnix = pkgs.deadnix;
      packages.healthcheck = pkgs.writeShellApplication {
        name = "healthcheck";
        runtimeInputs = with pkgs; [
          curl
          dnsutils
          gnugrep
          gnused
          iputils
          jq
          openssh
        ];
        text = ''exec ${../../scripts/healthcheck.sh} "$@"'';
      };
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
        shellHook = config.pre-commit.installationScript;
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
