{
  aspects.homeManager.ssh = {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings = {
        # Global defaults
        "*" = {
          AddKeysToAgent = "yes";
          ServerAliveInterval = 60;
          ServerAliveCountMax = 3;
          ControlMaster = "auto";
          ControlPath = "~/.ssh/sockets/%r@%h-%p";
          ControlPersist = "600";
        };
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
          ForwardAgent = true;
        };

        zbook = {
          User = "krzysiek";
          IdentityFile = "~/.ssh/zbook_ed25519";
          IdentitiesOnly = true;
          ForwardAgent = true;
        };
      };
    };

    # Create SSH socket directory
    home.file.".ssh/sockets/.keep".text = "";
  };
}
