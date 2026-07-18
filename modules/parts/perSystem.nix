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
        localSystem = { inherit system; };
        config.allowUnfree = true;
        overlays = [ ];
      };
      healthcheck = pkgs.writeShellApplication {
        name = "healthcheck";
        # The source-level directive documents the same intentional remote
        # argv expansion, but writeShellApplication prepends its own header so
        # ShellCheck no longer treats that directive as file-wide.
        excludeShellChecks = [ "SC2029" ];
        runtimeInputs = with pkgs; [
          curl
          dnsutils
          gnugrep
          gnused
          iputils
          jq
          openssh
        ];
        text = builtins.readFile ../../scripts/healthcheck.sh;
      };
      recover-secrets = pkgs.writeShellApplication {
        name = "recover-secrets";
        runtimeInputs = with pkgs; [
          coreutils
          git
          rage
        ];
        text = builtins.readFile ../../scripts/recover-secrets.sh;
      };
      set-tailscale-keys = pkgs.writeShellApplication {
        name = "set-tailscale-keys";
        runtimeInputs = with pkgs; [
          coreutils
          git
          nix
          rage
        ];
        text = builtins.readFile ../../scripts/set-tailscale-keys.sh;
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
            excludes = [ ".*\.age$" ];
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
          gitleaks = {
            enable = true;
            # git-hooks.nix has no built-in gitleaks hook in this revision, so
            # define it manually. We use `protect --staged` which is the
            # canonical pre-commit method: it inspects only the staged diff
            # (what would be committed), not the entire working tree.
            #
            # We intentionally do NOT pass --config: gitleaks 8.30.1 does not
            # honor `useDefault`/`extendDefault` in a custom config, so any
            # custom .gitleaks.toml silently disables ALL built-in rules.
            # The built-in rule set scans this repo cleanly; false positives
            # can be suppressed via .gitleaksignore.
            package = pkgs.gitleaks;
            entry = "${pkgs.gitleaks}/bin/gitleaks protect --no-banner --staged";
            # gitleaks runs its own git diff to find staged content; don't let
            # pre-commit append file names which it would treat as arguments.
            pass_filenames = false;
          };
        };
      };
      treefmt.config = {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
      };
      formatter = config.treefmt.build.wrapper;

      packages = {
        # Expose the scanner from this flake's locked nixpkgs input. Using the
        # registry shorthand `nixpkgs#gitleaks` would select the caller's
        # registry revision instead of the reviewed flake.lock revision.
        inherit (pkgs) deadnix gitleaks;
        inherit healthcheck recover-secrets set-tailscale-keys;
        command-code = pkgs'.callPackage ../../modules/_pkgs/command-code.nix { };
        gcx = pkgs'.callPackage ../../modules/_pkgs/gcx.nix { };
      };

      apps = {
        gitleaks = {
          type = "app";
          program = pkgs.lib.getExe pkgs.gitleaks;
          meta.description = "Scan repository content for credentials and secrets";
        };
        healthcheck = {
          type = "app";
          program = pkgs.lib.getExe healthcheck;
          meta.description = "Run role-aware post-deployment checks over SSH";
        };
        recover-secrets = {
          type = "app";
          program = pkgs.lib.getExe recover-secrets;
          meta.description = "Recover master-encrypted secrets from historical host ciphertext";
        };
        set-tailscale-keys = {
          type = "app";
          program = pkgs.lib.getExe set-tailscale-keys;
          meta.description = "Encrypt per-host Tailscale keys and run agenix-rekey";
        };
      };

      checks = {
        # `path:.` includes local VCS metadata, unlike the normal Git flake
        # source used by CI. Filter it before treefmt so a generated hook under
        # `.git/` can never become formatting input or a sandbox dependency.
        treefmt = pkgs.lib.mkForce (config.treefmt.build.check (pkgs.lib.cleanSource inputs.self));
        formatting = config.treefmt.build.check (pkgs.lib.cleanSource inputs.self);
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
        dashboard-renderer =
          pkgs.runCommand "dashboard-renderer-test"
            {
              buildInputs = [ pkgs.python3 ];
            }
            ''
              cp ${../../lib/observability/render_dashboard.py} render_dashboard.py
              cp ${../../lib/observability/render_dashboard_test.py} render_dashboard_test.py
              python3 -m unittest render_dashboard_test
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

        # Regression check for maintenance hosts that do not enable
        # observability: free-space-check's ReadWritePaths must exist before
        # systemd starts the service.
        maintenance-paths =
          let
            zbook = inputs.self.nixosConfigurations.zbook.config;
            requiredRule = "d /var/lib/prometheus/textfiles 0755 - - -";
          in
          pkgs.runCommand "maintenance-paths-test"
            {
              nativeBuildInputs = [ pkgs.jq ];
              rules = builtins.toJSON zbook.systemd.tmpfiles.rules;
            }
            ''
              if ! jq -e --arg rule '${requiredRule}' 'index($rule) != null' <<< "$rules" >/dev/null; then
                echo "missing maintenance tmpfiles rule: ${requiredRule}" >&2
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
          pkgs.just
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
