# Reboot-level proof for the production preservation and Btrfs rollback aspect.
# The VM prepares an encrypted test disk, then boots the real initrd rollback
# unit twice.  TPM and Secure Boot are deliberately outside this test's claim.
{ config, inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;
      persistence = config.aspects.nixos.persistence;
      runKvmTest = import ../../lib/testing/run-kvm-test.nix { inherit pkgs; };
      kvmChecks = import ../../lib/testing/kvm-checks.nix;

      testInventory = {
        preservation.preserveAt."/persist" = {
          directories = [
            {
              directory = "/etc/ssh";
              inInitrd = true;
              mode = "0700";
            }
            {
              directory = "/var/lib/dnsmasq";
              user = "dnsmasq-test";
              group = "dnsmasq-test";
              mode = "0750";
            }
          ];
          files = [
            {
              file = "/etc/machine-id";
              inInitrd = true;
            }
          ];
          users.alice.directories = [
            {
              directory = ".local/state/example";
              mode = "0700";
            }
          ];
        };
      };

      commonNode =
        { lib, ... }:
        {
          imports = [
            persistence
            inputs.agenix.nixosModules.default
          ];

          boot.initrd.systemd.enable = true;
          # qemu-vm intentionally clears LUKS devices with mkVMOverride (10).
          # This test is specifically about encrypted-root boot, so its
          # fixture must take precedence over that test-framework default.
          boot.initrd.luks.devices = lib.mkOverride 5 {
            crypted = {
              device = "/dev/vdb";
              keyFile = "/dev/vdc";
              keyFileSize = 25;
              tryEmptyPassphrase = false;
            };
          };

          fileSystems = {
            "/" = {
              device = lib.mkForce "/dev/mapper/crypted";
              fsType = lib.mkForce "btrfs";
              options = lib.mkForce [ "subvol=root" ];
            };
            "/persist" = {
              device = lib.mkForce "/dev/mapper/crypted";
              fsType = lib.mkForce "btrfs";
              options = lib.mkForce [
                "subvol=persist"
                "x-initrd.mount"
              ];
              neededForBoot = true;
            };
          };

          age.identityPaths = lib.mkForce [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

          users = {
            mutableUsers = false;
            users = {
              alice = {
                isNormalUser = true;
                uid = 1000;
              };
              dnsmasq-test = {
                isSystemUser = true;
                uid = 992;
                group = "dnsmasq-test";
              };
            };
            groups.dnsmasq-test.gid = 992;
          };

          system.stateVersion = "26.05";
        };

      negativeSystem = inputs.nixpkgs.lib.nixosSystem {
        system = pkgs.stdenv.hostPlatform.system;
        modules = [
          commonNode
          testInventory
          ../../tests/impermanence/require-early-persist.nix
          ../../tests/impermanence/missing-early-persist.nix
        ];
      };
      earlyPersistAssertion = lib.findFirst (
        assertion: assertion.message == "impermanence fixture: /persist must be mounted in the initrd"
      ) null negativeSystem.config.assertions;
      negativeEvaluation = builtins.tryEval negativeSystem.config.system.build.toplevel;
    in
    {
      checks = {
        ${kvmChecks.impermanenceVm} = runKvmTest {
          name = kvmChecks.impermanenceVm;

          nodes.machine =
            { pkgs, ... }:
            {
              # The default test root boots once only to create the realistic
              # LUKS/Btrfs fixture.  Subsequent boots use this disk as root.
              virtualisation = {
                # vdb is the encrypted filesystem; vdc models a separate
                # non-empty key device available to the initrd.
                emptyDiskImages = [
                  1024
                  1
                ];
                useBootLoader = true;
                useEFIBoot = true;
                mountHostNixStore = true;
              };
              boot.loader.systemd-boot.enable = true;
              environment.systemPackages = [
                pkgs.btrfs-progs
                pkgs.cryptsetup
                pkgs.gnugrep
                pkgs.openssh
              ];

              specialisation.impermanent.configuration = {
                imports = [
                  commonNode
                  testInventory
                ];
                virtualisation = {
                  rootDevice = lib.mkForce "/dev/mapper/crypted";
                  fileSystems = {
                    "/" = {
                      fsType = lib.mkForce "btrfs";
                      options = lib.mkForce [ "subvol=root" ];
                    };
                    "/persist" = {
                      device = lib.mkForce "/dev/mapper/crypted";
                      fsType = lib.mkForce "btrfs";
                      neededForBoot = lib.mkForce true;
                      options = lib.mkForce [
                        "subvol=persist"
                        "x-initrd.mount"
                      ];
                    };
                  };
                };
              };
            };

          testScript =
            { nodes, ... }:
            let
              # `specialisation.<name>.configuration` is the nested module
              # definition, not its evaluated system.  The built closure lives
              # under the base toplevel and contains the real LUKS/Btrfs initrd.
              impermanent = "${nodes.machine.system.build.toplevel}/specialisation/impermanent";
            in
            ''
              machine.start(allow_reboot=True)
              machine.succeed("grep -qw kvm-clock /sys/devices/system/clocksource/clocksource0/available_clocksource")
              machine.wait_for_unit("multi-user.target")

              # Build the same encrypted Btrfs shape used in production.  The
              # empty root snapshot is taken once, before mutable state exists.
              # Write the synthetic non-empty key to the separate fixture key
              # device. Production unlock policy and secrets are not imported.
              machine.succeed("printf fixture-only-nonempty-key > /dev/vdc")
              machine.succeed("cryptsetup luksFormat --batch-mode --key-file /dev/vdc --keyfile-size 25 /dev/vdb")
              machine.succeed("cryptsetup open --type luks --key-file /dev/vdc --keyfile-size 25 /dev/vdb crypted")
              machine.succeed("mkfs.btrfs -f /dev/mapper/crypted")
              machine.succeed("mkdir -p /mnt/test-disk && mount /dev/mapper/crypted /mnt/test-disk")
              machine.succeed("btrfs subvolume create /mnt/test-disk/root")
              machine.succeed("btrfs subvolume create /mnt/test-disk/persist")
              machine.succeed("btrfs subvolume snapshot -r /mnt/test-disk/root /mnt/test-disk/root-blank")
              machine.succeed("umount /mnt/test-disk && cryptsetup close crypted")

              machine.succeed("${impermanent}/bin/switch-to-configuration boot")
              machine.succeed("sync")
              # Select the specialization through systemd-boot's on-disk
              # configuration, then use the driver's native reboot path.  The
              # latter reconnects the shell without parsing firmware console
              # escape sequences.
              machine.succeed("entry=$(grep -lF 'title NixOS (impermanent)' /boot/loader/entries/*.conf); test \"$(printf '%s\\n' \"$entry\" | wc -l)\" -eq 1; entry=$(basename \"$entry\"); printf 'default %s\\ntimeout 0\\n' \"$entry\" > /boot/loader/loader.conf")
              machine.reboot()
              machine.wait_for_unit("multi-user.target")
              machine.succeed("grep -qw kvm-clock /sys/devices/system/clocksource/clocksource0/available_clocksource")

              machine.succeed("test \"$(findmnt -n -o FSTYPE /)\" = btrfs")

              # Distinct values make accidental cross-path assertions obvious.
              machine.succeed("printf ephemeral > /root-sentinel")
              machine.succeed("mkdir -p /var/lib/undeclared && printf undeclared > /var/lib/undeclared/state")
              machine.succeed("printf durable-system > /var/lib/dnsmasq/leases")
              machine.succeed("printf durable-user > /home/alice/.local/state/example/state")
              machine.succeed("rm -f /etc/ssh/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key.pub; ssh-keygen -q -t ed25519 -N \"\" -f /etc/ssh/ssh_host_ed25519_key; cp /etc/ssh/ssh_host_ed25519_key /persist/expected-host-key")
              machine.succeed("chown dnsmasq-test:dnsmasq-test /var/lib/dnsmasq/leases")
              machine.succeed("chmod 0640 /var/lib/dnsmasq/leases")
              machine.succeed("sync")
              machine.reboot()
              machine.wait_for_unit("multi-user.target")

              machine.fail("test -e /root-sentinel")
              machine.fail("test -e /var/lib/undeclared/state")
              machine.succeed("grep -Fx durable-system /var/lib/dnsmasq/leases")
              machine.succeed("grep -Fx durable-user /home/alice/.local/state/example/state")
              machine.succeed("cmp /etc/ssh/ssh_host_ed25519_key /persist/expected-host-key")
              machine.succeed("test \"$(stat -c '%U:%G:%a' /var/lib/dnsmasq)\" = 'dnsmasq-test:dnsmasq-test:750'")
              machine.succeed("test \"$(stat -c '%U:%G:%a' /var/lib/dnsmasq/leases)\" = 'dnsmasq-test:dnsmasq-test:640'")
              machine.succeed("test \"$(stat -c '%U:%G:%a' /home/alice/.local/state/example)\" = 'alice:users:700'")

              # A second completed rollback catches one-shot bootstrap effects.
              machine.succeed("printf second-ephemeral > /second-root-sentinel")
              machine.succeed("sync")
              machine.reboot()
              machine.wait_for_unit("multi-user.target")
              machine.fail("test -e /second-root-sentinel")
              machine.succeed("grep -Fx durable-system /var/lib/dnsmasq/leases")
            '';
        };

        # NixOS assertions fail while the child system is evaluated, before a
        # failing derivation can exist.  tryEval is therefore the precise
        # negative-test API here: the normal check exists only if evaluation of
        # the named mutation failed as intended.
        impermanence-missing-early-persist =
          assert earlyPersistAssertion != null && !earlyPersistAssertion.assertion;
          assert !negativeEvaluation.success;
          pkgs.runCommand "impermanence-missing-early-persist" { } "touch $out";
      };
    };
}
