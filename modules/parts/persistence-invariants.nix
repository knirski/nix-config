# Evaluation checks for the state that must survive the impermanent root.
#
# The inventories are deliberately explicit. A generic "everything persisted is
# backed up" rule would incorrectly reject disposable logs and caches, while an
# inferred service list could let a renamed state directory escape review.
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
      zbookPersistence = import ../../lib/zbook-persistence.nix;

      preserve = host: hosts.${host}.preservation.preserveAt."/persist";
      bindDirectories =
        host:
        map (entry: entry.directory) (
          lib.filter (entry: entry.how == "bindmount") (preserve host).directories
        );
      bindFiles =
        host: map (entry: entry.file) (lib.filter (entry: entry.how == "bindmount") (preserve host).files);
      userDirectories =
        host: user:
        map (entry: entry.directory) (
          lib.filter (entry: entry.how == "bindmount") (preserve host).users.${user}.directories
        );
      directoryEntry =
        host: path: lib.findFirst (entry: entry.directory == path) null (preserve host).directories;
      fileEntry = host: path: lib.findFirst (entry: entry.file == path) null (preserve host).files;
      setEqual = left: right: lib.sort builtins.lessThan left == lib.sort builtins.lessThan right;

      commonDirectories = [
        "/var/lib/nixos"
        "/etc/ssh"
        "/var/lib/tailscale"
        "/var/lib/sbctl"
        "/etc/restic"
      ];
      soyoStateDirectories = [
        "/var/lib/dnsmasq"
        "/var/lib/private/alloy"
        "/var/lib/grafana"
        "/var/lib/loki"
        "/var/lib/prometheus"
        "/var/lib/tempo"
      ];
      # Losing these paths would lose operator data or non-reproducible program
      # state, so the check requires them to remain in the inventory.
      zbookRequiredDurableDirectories = map (path: "/home/krzysiek/${path}") zbookPersistence.durable;
      # These paths are intentionally persisted for convenience but are not a
      # durability contract: caches can be regenerated, tmp/download content is
      # user-managed, and the application/hyprland paths may become obsolete.
      # New persisted paths must be classified in one of these two inventories.
      zbookBestEffortDirectories = map (path: "/home/krzysiek/${path}") zbookPersistence.bestEffort;
      zbookClassifiedDirectories = zbookRequiredDurableDirectories ++ zbookBestEffortDirectories;

      # Pictures/Screenshots is the sole allowed nested preservation entry. It
      # is retained deliberately as a named mount despite Pictures already being
      # durable; any new overlap needs an explicit policy decision here.
      allowedZbookOverlaps = [
        "/home/krzysiek/Pictures -> /home/krzysiek/Pictures/Screenshots"
      ];
      zbookDirectoryOverlaps =
        let
          directories = userDirectories "zbook" "krzysiek";
        in
        lib.concatMap (
          parent:
          map (child: "${parent} -> ${child}") (
            lib.filter (child: child != parent && lib.hasPrefix "${parent}/" child) directories
          )
        ) directories;

      # Restic backs up /persist wholesale. These are the only intentionally
      # persisted-but-not-backed-up classes: operational logs, local shell
      # Bash history, and the reproducible direnv cache. Zsh history remains in
      # the backup because it is not matched by the Bash-specific exclusion.
      deliberateBackupExclusions = [
        "/persist/var/log/*"
        "/persist/home/*/.bash_history"
        "/persist/home/*/.local/share/direnv/*"
      ];

      backup = host: hosts.${host}.services.restic.backups.${host};
      backupSource = host: hosts.${host}.lanAppliance.services.backup;
      btrbk = host: hosts.${host}.services.btrbk.instances.${host};
      agenixIdentity = "/persist/etc/ssh/ssh_host_ed25519_key";

      expectedBtrbk = {
        soyo = {
          sources = [
            "persist:/snapshots/persist"
            "root:/snapshots/root"
          ];
          subvolumes = [
            "persist:/snapshots/persist"
            "root:/snapshots/root"
          ];
        };
        zbook = {
          sources = [ "persist:/snapshots/persist" ];
          subvolumes = [ "persist:/snapshots/persist" ];
        };
      };

      checks =
        lib.concatMap (
          host:
          let
            config = hosts.${host};
          in
          [
            {
              name = "${host}: /persist is needed for early boot";
              pass = config.fileSystems."/persist".neededForBoot;
            }
            {
              name = "${host}: /persist is mounted by the initrd";
              pass = lib.elem "x-initrd.mount" config.fileSystems."/persist".options;
            }
            {
              name = "${host}: agenix reads the persisted SSH host key";
              pass = setEqual config.age.identityPaths [ agenixIdentity ];
            }
            {
              name = "${host}: /etc/ssh is persisted in the initrd";
              pass =
                let
                  entry = directoryEntry host "/etc/ssh";
                in
                entry != null && entry.inInitrd;
            }
            {
              name = "${host}: /etc/machine-id is persisted in the initrd";
              pass =
                let
                  entry = fileEntry host "/etc/machine-id";
                in
                entry != null && entry.inInitrd;
            }
            {
              name = "${host}: common system state is persisted";
              pass = lib.all (path: lib.elem path (bindDirectories host)) commonDirectories;
            }
            {
              name = "${host}: machine-id is in the persisted file inventory";
              pass = lib.elem "/etc/machine-id" (bindFiles host);
            }
            {
              name = "${host}: restic backs up the complete persistence tree";
              pass = setEqual (backup host).paths [ "/persist" ];
            }
            {
              name = "${host}: only documented persisted state is excluded from restic";
              pass = setEqual (backup host).exclude deliberateBackupExclusions;
            }
            {
              name = "${host}: restic source option names the persisted SSH key";
              pass = (backupSource host).restic.sshKeyFile == "/persist/etc/restic/ssh-key";
            }
            {
              name = "${host}: restic known_hosts parent is persisted";
              pass = lib.elem "/etc/restic" (bindDirectories host);
            }
            {
              name = "${host}: btrbk source inventory has the intended snapshot paths";
              pass = setEqual (map (entry: "${entry.name}:${entry.snapshotDir}")
                (backupSource host).btrbk.subvolumes
              ) expectedBtrbk.${host}.sources;
            }
            {
              name = "${host}: btrbk instance is enabled daily";
              pass = (btrbk host).onCalendar == "daily" && !(btrbk host).snapshotOnly;
            }
            {
              name = "${host}: generated btrbk sources and snapshots match policy";
              pass =
                let
                  generated = (btrbk host).settings.volume."/".subvolume;
                in
                setEqual (lib.mapAttrsToList (
                  name: value: "${name}:${value.snapshot_dir}"
                ) generated) expectedBtrbk.${host}.subvolumes;
            }
          ]
        ) (builtins.attrNames hosts)
        ++ [
          {
            name = "soyo: all stateful DNS and observability services are persisted";
            pass = lib.all (path: lib.elem path (bindDirectories "soyo")) soyoStateDirectories;
          }
          {
            name = "soyo: state directories keep service ownership and modes";
            pass =
              lib.all
                (
                  expected:
                  let
                    entry = directoryEntry "soyo" expected.path;
                  in
                  entry != null
                  && entry.user == expected.user
                  && entry.group == expected.group
                  && entry.mode == expected.mode
                )
                [
                  {
                    path = "/var/lib/grafana";
                    user = "grafana";
                    group = "grafana";
                    mode = "0750";
                  }
                  {
                    path = "/var/lib/loki";
                    user = "loki";
                    group = "loki";
                    mode = "0750";
                  }
                  {
                    path = "/var/lib/tempo";
                    user = "tempo";
                    group = "tempo";
                    mode = "0750";
                  }
                  {
                    path = "/var/lib/prometheus";
                    user = "prometheus";
                    group = "prometheus";
                    mode = "0750";
                  }
                ];
          }
          {
            name = "both hosts: sbctl keys remain root-only";
            pass = lib.all (
              host:
              let
                entry = directoryEntry host "/var/lib/sbctl";
              in
              entry != null && entry.user == "root" && entry.group == "root" && entry.mode == "0700"
            ) (builtins.attrNames hosts);
          }
          {
            name = "zbook: required durable user data is persisted";
            pass = lib.all (
              path: lib.elem path (userDirectories "zbook" "krzysiek")
            ) zbookRequiredDurableDirectories;
          }
          {
            name = "zbook: every persisted user directory has a durability classification";
            pass = lib.all (path: lib.elem path zbookClassifiedDirectories) (
              userDirectories "zbook" "krzysiek"
            );
          }
          {
            name = "zbook: nested persistence follows the explicit overlap policy";
            pass = setEqual zbookDirectoryOverlaps allowedZbookOverlaps;
          }
          {
            name = "zbook: shell histories are persisted";
            pass =
              let
                files = map (entry: entry.file) (preserve "zbook").users.krzysiek.files;
              in
              lib.all (path: lib.elem path files) [
                "/home/krzysiek/.bash_history"
                "/home/krzysiek/.zsh_history"
              ];
          }
        ];

      failures = map (check: check.name) (builtins.filter (check: !check.pass) checks);
      failureText = lib.concatMapStringsSep "\n" (name: "- ${name}") failures;
    in
    {
      checks.persistence-invariants =
        pkgs.runCommand "persistence-invariants-test"
          {
            failed = if failures == [ ] then "0" else "1";
            inherit failureText;
            passAsFile = [ "failureText" ];
          }
          ''
            if [ "$failed" != 0 ]; then
              echo "ERROR: persistence and backup invariants failed:" >&2
              cat "$failureTextPath" >&2
              exit 1
            fi
            touch "$out"
          '';
    };
}
