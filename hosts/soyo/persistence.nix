# We deliberately do NOT persist /etc/{passwd,shadow,group,...}: with
# users.mutableUsers = false and hashedPasswordFile, NixOS regenerates them
# declaratively each boot from the agenix secrets. /var/lib/nixos is persisted
# so declarative UID/GID assignments stay stable.
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
      "/var/lib/dnsmasq"
      "/var/log"
      "/etc/restic"
    ];
    files = [
      {
        file = "/etc/machine-id";
        inInitrd = true;
      }
    ];
    users.krzysiek = {
      directories = [
        {
          directory = ".ssh";
          mode = "0700";
        }
        ".local/share/direnv"
      ];
      files = [ ".bash_history" ];
    };
  };
}
