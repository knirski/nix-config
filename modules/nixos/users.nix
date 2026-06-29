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
    age.secrets = {
      root-password.file = ../../secrets/root-password.age;
      krzysiek-password.file = ../../secrets/krzysiek-password.age;
      restic-password.file = ../../secrets/restic-password.age;
      ntfy-token.file = ../../secrets/ntfy-token.age;
    };
  };
}
