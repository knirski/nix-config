# flake-parts module: dev shell, formatter, and repo checks.
{ inputs, ... }:
{
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
    let
      # PerSystem pkgs with unfree allowed (needed for packages.command-code).
      pkgs' = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      pre-commit.settings = {
        hooks = {
          treefmt.enable = true;
          deadnix.enable = true;
          statix.enable = true;
          typos = {
            enable = true;
            excludes = [ ".*\\.age$" ];
            settings.config = {
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
          check-merge-conflicts.enable = true;
          end-of-file-fixer.enable = true;
          end-of-file-fixer.excludes = [
            "facter\\.json$"
            "\\.svg$"
            "\\.age$"
          ];
          actionlint.enable = true;
          shellcheck.enable = true;
          markdownlint = {
            enable = true;
            settings.configuration = {
              MD013 = false;
              MD033 = false;
              MD060 = false;
              MD029 = false;
              MD031 = false;
              MD032 = false;
            };
            excludes = [ "\.commandcode" ];
          };
          ruff.enable = true;
        };
      };
      treefmt.config = {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
      };
      formatter = config.treefmt.build.wrapper;

      packages = {
        inherit (pkgs) deadnix;
        command-code = pkgs'.callPackage ../../modules/_pkgs/command-code.nix { };
        healthcheck = pkgs.writeShellApplication {
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
      };

      checks = {
        formatting = config.treefmt.build.check inputs.self;
        lan-inventory =
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

        # Option-namespace test: verify that each host declares the
        # lanAppliance.services.* options matching the aspects it toggles.
        # Missing = silent No-Op when a host data file sets a wrong namespace.
        dendritic-options =
          let
            # Host → expected option list (matching host assembler toggles).
            hostOpts = {
              soyo = [
                "lanAppliance.services.backup"
                "lanAppliance.services.blocky"
                "lanAppliance.services.dhcp"
                "lanAppliance.services.maintenance"
                "lanAppliance.services.observability"
                "lanAppliance.services.remoteUnlock"
                "lanAppliance.services.ssh"
                "lanAppliance.services.tailscale"
              ];
              zbook = [
                "lanAppliance.services.backup"
                "lanAppliance.services.maintenance"
                "lanAppliance.services.nvidia"
                "lanAppliance.services.ssh"
                "lanAppliance.services.tailscale"
              ];
            };

            missing =
              hostName: opt:
              let
                path = pkgs.lib.splitString "." opt;
                ok = pkgs.lib.hasAttrByPath path inputs.self.nixosConfigurations.${hostName}.config;
              in
              if ok then null else "${hostName}:${opt}";

            missingList = pkgs.lib.concatStringsSep "\n" (
              pkgs.lib.filter (x: x != null) (
                pkgs.lib.concatMap (hostName: map (missing hostName) hostOpts.${hostName}) [
                  "soyo"
                  "zbook"
                ]
              )
            );

            ok = missingList == "";
          in
          pkgs.runCommand "dendritic-options-test"
            {
              inherit ok;
              passAsFile = [ "missingList" ];
              inherit missingList;
            }
            ''
              if [ "$ok" != "1" ]; then
                echo "ERROR: some required lanAppliance.services.* options are undeclared:" >&2
                cat "$missingListPath" >&2
                exit 1
              fi
              touch "$out"
            '';
      };

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
          pkgs.nodejs
          pkgs.sbctl
          inputs.agenix-rekey.packages.${system}.default
          inputs.deploy-rs.packages.${system}.default
        ];
      };
    };
}
