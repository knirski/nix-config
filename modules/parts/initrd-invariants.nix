# Verify the declared remote-unlock interface without dereferencing a private
# key. Runtime key sources remain plain strings specifically so Nix does not
# copy their payloads into the store during evaluation or a normal build.
# A connectivity VM is deliberately omitted: normal boot closes stage 1 too
# quickly for a reliable probe, while a fixture encrypted disk would exercise
# neither the physical TPM nor the real break-glass storage path.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;
      soyo = inputs.self.nixosConfigurations.soyo.config;
      remote = soyo.lanAppliance.services.remoteUnlock;
      initrd = soyo.boot.initrd;
      sshd = initrd.systemd.services.sshd;
      copySecrets = initrd.systemd.services.initrd-nixos-copy-secrets;
      rollback = initrd.systemd.services.rollback-root;
      initrdKey = "/boot/initrd-ssh/ssh_host_ed25519_key";
      stage2Identity = "/persist/etc/ssh/ssh_host_ed25519_key";
      operatorIdentity = "/etc/agenix-rekey/master-identity";
      operatorIdentities = map (entry: entry.identity) soyo.age.rekey.masterIdentities;

      setEqual = left: right: lib.sort builtins.lessThan left == lib.sort builtins.lessThan right;
      contains = needle: haystack: lib.hasInfix needle haystack;
      sourceIsRuntimeString = source: builtins.isString source && !(lib.hasPrefix "/nix/store/" source);

      summary = {
        inherit (remote) authorizedKeys;
        keyMapping = initrd.secrets;
        sshdAfter = sshd.after;
      };
      contract =
        value:
        value.authorizedKeys != [ ]
        && value.keyMapping == { ${initrdKey} = initrdKey; }
        && lib.elem "initrd-nixos-copy-secrets.service" value.sshdAfter;
      mutations = import ../../tests/initrd/mutations.nix;
      ineffectiveMutations = map (mutation: mutation.name) (
        lib.filter (mutation: contract (mutation.mutate summary)) mutations
      );

      graph = {
        "sshd.service" = sshd.after;
        "initrd-nixos-copy-secrets.service" = [ ];
        "cryptsetup-pre.target" = [ "initrd-nixos-copy-secrets.service" ];
        "systemd-cryptsetup@crypted.service" = [ "cryptsetup-pre.target" ];
        "rollback-root.service" = rollback.requires ++ rollback.after;
        "sysroot.mount" = [ "rollback-root.service" ];
        "network.target" = [ ];
      };
      graphJson = pkgs.writeText "initrd-recovery-graph.json" (builtins.toJSON graph);

      checks = [
        {
          name = "remote unlock is enabled only on the systemd initrd";
          pass = remote.enable && initrd.systemd.enable && initrd.network.enable && initrd.network.ssh.enable;
        }
        {
          name = "initrd SSH uses its dedicated port";
          pass =
            initrd.network.ssh.port == 2222
            && contains "Port 2222" initrd.systemd.contents."/etc/ssh/sshd_config".text;
        }
        {
          name = "initrd SSH key is a runtime-only string mapping";
          pass =
            initrd.network.ssh.hostKeys == [ initrdKey ]
            && initrd.secrets == { ${initrdKey} = initrdKey; }
            && sourceIsRuntimeString initrd.secrets.${initrdKey};
        }
        {
          name = "initrd, stage-2, and operator identities remain separate";
          pass =
            initrdKey != stage2Identity
            && initrdKey != operatorIdentity
            && soyo.age.identityPaths == [ stage2Identity ]
            && operatorIdentities == [ operatorIdentity ]
            && lib.all sourceIsRuntimeString (soyo.age.identityPaths ++ operatorIdentities);
        }
        {
          name = "authorized public keys reach the generated initrd sshd configuration";
          pass =
            remote.authorizedKeys != [ ]
            && initrd.network.ssh.authorizedKeys == remote.authorizedKeys
            &&
              initrd.systemd.contents."/etc/ssh/authorized_keys.d/root".text
              == lib.concatStringsSep "\n" remote.authorizedKeys;
        }
        {
          name = "sshd waits for networking and runtime secret copying";
          pass =
            setEqual sshd.after [
              "initrd-nixos-copy-secrets.service"
              "network.target"
            ]
            && lib.elem "initrd.target" sshd.wantedBy
            && sshd.unitConfig.DefaultDependencies == false;
        }
        {
          name = "secret copying runs early and before cryptsetup";
          pass =
            lib.elem "sysinit.target" copySecrets.wantedBy
            && lib.elem "cryptsetup-pre.target" copySecrets.before
            && copySecrets.unitConfig.DefaultDependencies == false
            && copySecrets.serviceConfig.Type == "oneshot";
        }
        {
          name = "LAN and direct-link rescue addresses share only the selected interface";
          pass =
            remote.interface == "enp1s0"
            && setEqual initrd.systemd.network.networks."10-enp1s0".address [
              remote.lanAddress
              remote.rescueAddress
            ]
            && initrd.systemd.network.networks."10-enp1s0".routes == [ { Gateway = remote.gatewayAddress; } ];
        }
        {
          name = "encrypted root retains TPM and passphrase-capable cryptsetup wiring";
          pass =
            initrd.luks.devices.crypted.device == "/dev/disk/by-partlabel/luks"
            && lib.elem "tpm2-device=auto" initrd.luks.devices.crypted.crypttabExtraOpts;
        }
        {
          name = "persistent state and rollback precede root consumers";
          pass =
            soyo.fileSystems."/persist".neededForBoot
            && lib.elem "x-initrd.mount" soyo.fileSystems."/persist".options
            && rollback.after == [ "systemd-cryptsetup@crypted.service" ]
            && rollback.before == [ "sysroot.mount" ]
            && rollback.unitConfig.DefaultDependencies == "no";
        }
        {
          name = "mutation fixtures each break the recovery contract";
          pass = contract summary && ineffectiveMutations == [ ];
        }
      ];
      failed = map (check: check.name) (lib.filter (check: !check.pass) checks);
    in
    {
      checks.initrd-recovery-invariants =
        assert
          failed == [ ]
          || throw "Initrd recovery invariants failed: ${builtins.concatStringsSep ", " failed}";
        pkgs.runCommand "initrd-recovery-invariants" { nativeBuildInputs = [ pkgs.python3 ]; } ''
          python3 - ${graphJson} <<'PY'
          import json
          import sys

          graph = json.load(open(sys.argv[1], encoding="utf-8"))
          known = set(graph)
          graph = {node: [dependency for dependency in dependencies if dependency in known]
                   for node, dependencies in graph.items()}

          visiting = set()
          visited = set()

          def visit(node):
              if node in visiting:
                  raise SystemExit(f"initrd dependency cycle reaches {node}")
              if node in visited:
                  return
              visiting.add(node)
              for dependency in graph[node]:
                  visit(dependency)
              visiting.remove(node)
              visited.add(node)

          for node in graph:
              visit(node)
          PY
          touch "$out"
        '';
    };
}
