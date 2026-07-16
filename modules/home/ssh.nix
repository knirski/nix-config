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
          # Security: reject connections to unknown hosts by default
          StrictHostKeyChecking = "ask";
        };
        # Select the GitHub key explicitly.  The global NixOS
        # AddKeysToAgent yes loads it into the running agent on first use.
        "github.com" = {
          User = "git";
          IdentityFile = "~/.ssh/zbook_ed25519";
          IdentitiesOnly = true;
          # GitHub's host keys are well-known
          StrictHostKeyChecking = "accept-new";
        };

        soyo = {
          User = "krzysiek";
          IdentityFile = "~/.ssh/soyo_ed25519";
          IdentitiesOnly = true;
          # ForwardAgent is acceptable on a trusted homelab LAN.
          # Use `ssh -A` for ad-hoc forwarding if you prefer not to set this.
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
