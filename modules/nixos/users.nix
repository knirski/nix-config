# User *policy* only. Per-user definitions and password secrets are host data
# (hosts/soyo/users.nix); the agenix secret inventory is added in Task 6.
{
  flake.modules.nixos.users = {
    users.mutableUsers = false;

    security.sudo = {
      enable = true;
      wheelNeedsPassword = true;
    };
  };
}
