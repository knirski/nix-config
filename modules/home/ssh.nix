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
        # Let OpenSSH use the platform's normal agent/default-key discovery.
        # A host-specific workstation key is not guaranteed to exist on
        # macbook or Ubuntu, so the shared aspect must not hardcode zbook's
        # private-key filename.
        "github.com" = {
          User = "git";
          # GitHub's host keys are well-known
          StrictHostKeyChecking = "accept-new";
        };

        soyo = {
          User = "krzysiek";
          IdentityFile = "~/.ssh/soyo_ed25519";
          IdentitiesOnly = true;
          # Agent forwarding is opt-in (`ssh -A`) because a compromised remote
          # host can use a forwarded agent to authenticate elsewhere.
          ForwardAgent = false;
        };

        zbook = {
          User = "krzysiek";
          IdentityFile = "~/.ssh/zbook_ed25519";
          IdentitiesOnly = true;
          ForwardAgent = false;
        };
      };
    };

    # Create SSH socket directory
    home.file.".ssh/sockets/.keep".text = "";
  };
}
