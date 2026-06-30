# User *policy* only. Per-user definitions and password secrets are host data
# (hosts/soyo/users.nix).
{
  flake.modules.nixos.users = {
    users.mutableUsers = false;

    security.sudo = {
      enable = true;
      wheelNeedsPassword = true;
    };

    # Paths resolve relative to this file: ../../secrets -> repo root /secrets.
    # rekeyFile points to the master-encrypted secret (encrypted with the
    # operator's key).  agenix-rekey auto-generates the per-host rekeyed
    # version (encrypted with the host's SSH key) and populates `file` from it.
    age.secrets = {
      root-password.rekeyFile = ../../secrets/root-password.age;
      krzysiek-password.rekeyFile = ../../secrets/krzysiek-password.age;
      restic-password.rekeyFile = ../../secrets/restic-password.age;
      ntfy-token.rekeyFile = ../../secrets/ntfy-token.age;
      ntfy-topic.rekeyFile = ../../secrets/ntfy-topic.age;
    };
  };
}
