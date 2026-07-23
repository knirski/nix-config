# User *policy* only. Per-user definitions and password secrets are host data
# (hosts/soyo/users.nix).
{
  aspects.nixos.users = {
    users.mutableUsers = false;

    security.sudo = {
      enable = true;
      # Passwordless sudo: required for remote deploy via --target-host.
      # SSH access is already key-only, so this doesn't weaken the auth
      # boundary — it avoids interactive password prompts during activation.
      wheelNeedsPassword = false;
    };

    # Paths resolve relative to this file: ../../secrets -> repo root /secrets.
    # rekeyFile points to the master-encrypted secret (encrypted with the
    # operator's key).  agenix-rekey auto-generates the per-host rekeyed
    # version (encrypted with the host's SSH key) and populates `file` from it.
    #
    # github-token is NOT declared here: it is only for gh/command-code/
    # development tooling, so it is declared in the per-host block of hosts
    # that enable aspects.homeManager.development (currently only zbook; see
    # modules/parts/zbook.nix). Soyo has no GitHub workflow and must not get
    # this secret.
    age.secrets = {
      root-password.rekeyFile = ../../secrets/root-password.age;
      krzysiek-password.rekeyFile = ../../secrets/krzysiek-password.age;
      ntfy-token.rekeyFile = ../../secrets/ntfy-token.age;
      ntfy-topic.rekeyFile = ../../secrets/ntfy-topic.age;
    };
  };
}
