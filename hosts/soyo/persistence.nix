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
      # Freshness markers for the nightly backup units (restic + btrbk). The
      # healthcheck's backup-freshness probe reads these; without persistence
      # every reboot resets them to "never ran" even when backups are healthy.
      # The btrbk marker dir is owned by the btrbk service user; restic's is
      # root-owned (preservation's default for plain-string entries).
      "/var/lib/restic-backups-soyo"
      {
        directory = "/var/lib/btrbk-soyo";
        user = "btrbk";
        group = "btrbk";
      }
      # Alloy uses DynamicUser + StateDirectory=alloy, which resolves to the
      # private state dir below. Persist the cursor so journal shipping resumes
      # from the last read entry instead of replaying a large backlog on boot.
      "/var/lib/private/alloy"
      # preservation generates tmpfiles entries for persisted directories, so
      # service ownership belongs here rather than in a second conflicting rule.
      {
        directory = "/var/lib/grafana";
        user = "grafana";
        group = "grafana";
        mode = "0750";
      }
      {
        directory = "/var/lib/loki";
        user = "loki";
        group = "loki";
        mode = "0750";
      }
      "/var/lib/tailscale"
      # sbctl stores the Secure Boot private keys here. If this directory is
      # wiped with the ephemeral root, future Limine updates cannot be signed.
      {
        directory = "/var/lib/sbctl";
        mode = "0700";
      }
      {
        directory = "/var/lib/tempo";
        user = "tempo";
        group = "tempo";
        mode = "0750";
      }
      {
        directory = "/var/lib/prometheus";
        user = "prometheus";
        group = "prometheus";
        mode = "0750";
      }
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
        {
          directory = ".agents";
          mode = "0700";
        }
        ".local/share/atuin"
        ".local/share/direnv"
        ".local/state/home-manager"
      ];
      files = [ ".bash_history" ];
    };
  };
}
