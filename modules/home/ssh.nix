{
  aspects.homeManager.ssh = {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings = {
        # Select the GitHub key explicitly.  The global NixOS
        # AddKeysToAgent yes loads it into the running agent on first use.
        "github.com" = {
          User = "git";
          IdentityFile = "~/.ssh/zbook_ed25519";
          IdentitiesOnly = true;
        };

        soyo = {
          User = "krzysiek";
          IdentityFile = "~/.ssh/soyo_ed25519";
          IdentitiesOnly = true;
        };

        zbook = {
          User = "krzysiek";
          IdentityFile = "~/.ssh/zbook_ed25519";
          IdentitiesOnly = true;
        };
      };
    };
  };
}
