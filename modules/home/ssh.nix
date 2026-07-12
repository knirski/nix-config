_: {
  aspects.homeManager.ssh = _: {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings = {
        # Select the GitHub key explicitly.  AddKeysToAgent loads the
        # passphrase-protected key into the already-running agent on first use.
        "github.com" = {
          User = "git";
          IdentityFile = "~/.ssh/zbook_ed25519";
          IdentitiesOnly = true;
          AddKeysToAgent = "yes";
        };

        soyo = {
          User = "krzysiek";
          IdentityFile = "~/.ssh/soyo_ed25519";
          IdentitiesOnly = true;
          AddKeysToAgent = "yes";
        };
      };
    };
  };
}
