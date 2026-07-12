# Shell has three distinct validation boundaries: NixOS-generated unit scripts,
# checked applications, and standalone source files.  Keep the distinctions
# executable so a new helper cannot silently bypass ShellCheck.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;
      hosts = {
        soyo = inputs.self.nixosConfigurations.soyo.config;
        zbook = inputs.self.nixosConfigurations.zbook.config;
      };
      generatedFields = [
        "script"
        "preStart"
        "postStart"
        "reload"
        "preStop"
        "postStop"
      ];
      generatedServices =
        services:
        lib.filterAttrs (
          _: service: lib.any (field: (service.${field} or "") != "") generatedFields
        ) services;
      strictExceptions = {
        soyo = [ "dnsmasq" ];
        zbook = [ "greetd" ];
      };
      strictViolations = lib.concatMap (
        host:
        let
          cfg = hosts.${host};
          services =
            (generatedServices cfg.systemd.services) // (generatedServices cfg.boot.initrd.systemd.services);
        in
        lib.mapAttrsToList (name: _: "${host}:${name}") (
          lib.filterAttrs (
            name: service: !service.enableStrictShellChecks && !(lib.elem name strictExceptions.${host})
          ) services
        )
      ) (builtins.attrNames hosts);
      execCommands =
        service:
        lib.flatten (
          map
            (
              field:
              lib.optional (builtins.hasAttr field service.serviceConfig) (
                builtins.getAttr field service.serviceConfig
              )
            )
            [
              "ExecStart"
              "ExecStartPre"
              "ExecStartPost"
              "ExecStop"
              "ExecStopPost"
              "ExecReload"
            ]
        );
      invalidExec =
        command: builtins.isString command && builtins.match "^[[:space:]]*[-+!:@]*/.*" command == null;
      # PATH-based commands in generated upstream units belong to nixpkgs.
      # This explicit list is the repository-owned Exec boundary: additions
      # require a deliberate inventory update and an absolute executable.
      repositoryExecServices = {
        soyo = [
          "grafana-alert-setup"
          "lan-inventory-exporter"
          "nix-store-optimise"
          "restic-backup-metric-bootstrap"
          "soyo-activation-trace"
          "soyo-boot-trace"
          "soyo-health-trace"
          "tailscale-auth"
        ];
        zbook = [ "nix-store-optimise" ];
      };
      execViolations = lib.concatMap (
        host:
        let
          services = hosts.${host}.systemd.services;
        in
        lib.concatMap (
          name: map (_: "${host}:${name}") (lib.filter invalidExec (execCommands services.${name}))
        ) repositoryExecServices.${host}
      ) (builtins.attrNames hosts);
    in
    {
      checks.shell-boundaries =
        assert lib.assertMsg (strictViolations == [ ])
          "generated systemd scripts without strict ShellCheck: ${lib.concatStringsSep ", " strictViolations}";
        assert lib.assertMsg (execViolations == [ ])
          "systemd Exec commands must begin with an absolute executable: ${lib.concatStringsSep ", " execViolations}";
        pkgs.runCommand "shell-boundaries"
          {
            nativeBuildInputs = [
              pkgs.python3
              pkgs.shellcheck
            ];
            src = lib.cleanSource inputs.self;
          }
          ''
            cp -R "$src" source
            chmod -R u+w source
            python3 source/tests/shell/check-boundaries.py source
            find source/scripts source/tests -type f -name '*.sh' -print0 \
              | xargs -0 shellcheck

            cp source/tests/shell/fixtures/unchecked-helper.nix.fixture source/unchecked-helper.nix
            if python3 source/tests/shell/check-boundaries.py source; then
              echo "unchecked writeShellScript mutation unexpectedly passed" >&2
              exit 1
            fi
            touch "$out"
          '';
    };
}
