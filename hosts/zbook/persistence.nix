let
  inventory = import ../../lib/zbook-persistence.nix;
in
{
  preservation.preserveAt."/persist" = {
    directories = [
      {
        directory = "/var/lib/nixos";
        inInitrd = true;
      }
      {
        directory = "/etc/ssh";
        inInitrd = true;
      }
      # sbctl stores the Secure Boot private keys here. If this directory is
      # wiped with the ephemeral root, future Limine updates cannot be signed.
      {
        directory = "/var/lib/sbctl";
        mode = "0700";
      }
      "/var/lib/tailscale"
      # /etc/restic stores the SSH key and known_hosts for restic remote backups.
      # Without this, the key vanishes on reboot and unattended backups fail.
      "/etc/restic"
      "/var/log"
      "/var/lib/dms-greeter"
    ];
    files = [
      {
        file = "/etc/machine-id";
        inInitrd = true;
      }
    ];
    users.krzysiek = {
      directories = map (
        directory:
        if directory == ".ssh" then
          {
            inherit directory;
            mode = "0700";
          }
        else
          directory
      ) inventory.all;
      files = [
        ".bash_history"
        ".zsh_history"
      ];
    };
  };
}
