{ inputs, ... }:
{
  flake.modules.nixos.persistence =
    { pkgs, ... }:
    {
      imports = [ inputs.preservation.nixosModules.preservation ];

      preservation.enable = true;

      # /persist must be mounted before stage-2 activation so agenix can read the
      # host key from its durable location (see age.identityPaths below).
      fileSystems."/persist".neededForBoot = true;

      # agenix decrypts using the durable host key, not the wiped /etc/ssh.
      age.identityPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

      # Erase-your-darlings on Btrfs: restore `root` from a blank snapshot each
      # boot. Ordered after the LUKS device opens and before the root is mounted.
      # Nested subvolumes (systemd/services create them under /var/lib) must be
      # deleted first or `btrfs subvolume delete root` fails.
      boot.initrd.systemd.services.rollback-root = {
        wantedBy = [ "initrd.target" ];
        after = [ "systemd-cryptsetup@crypted.service" ];
        before = [ "sysroot.mount" ];
        unitConfig.DefaultDependencies = "no";
        serviceConfig.Type = "oneshot";
        script = ''
          set -euo pipefail
          mkdir -p /mnt
          mount -o subvol=/ /dev/mapper/crypted /mnt

          # Canonical bootstrap: root-blank is the readonly empty snapshot taken
          # ONCE at install (see docs/install-soyo.md). Guard before destroying
          # root so a missing blank fails loud with root intact, not a brick.
          if [ ! -e /mnt/root-blank ]; then
            echo "rollback-root: /root-blank missing — create it at install:" >&2
            echo "  btrfs subvolume snapshot -r /mnt/root /mnt/root-blank" >&2
            umount /mnt
            exit 1
          fi

          # Delete nested subvolumes under the live root first (systemd/services
          # create them under /var/lib), or `btrfs subvolume delete root` fails.
          ${pkgs.btrfs-progs}/bin/btrfs subvolume list -o /mnt/root \
            | ${pkgs.coreutils}/bin/cut -f9 -d' ' \
            | while read -r sub; do
                ${pkgs.btrfs-progs}/bin/btrfs subvolume delete "/mnt/$sub"
              done

          ${pkgs.btrfs-progs}/bin/btrfs subvolume delete /mnt/root
          ${pkgs.btrfs-progs}/bin/btrfs subvolume snapshot /mnt/root-blank /mnt/root
          umount /mnt
        '';
      };
    };
}
