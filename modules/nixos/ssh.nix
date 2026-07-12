# Shared SSH lockdown aspect.
#
# Extracted from server.nix and workstation.nix — both had identical OpenSSH
# lockdown config. Toggle this in the host assembler once instead of
# duplicating the block in every role module that needs SSH.
{
  aspects.nixos.ssh =
    { lib, config, ... }:
    let
      cfg = config.lanAppliance.services.ssh;
    in
    {
      options.lanAppliance.services.ssh = {
        enable = lib.mkEnableOption "SSH server with key-only auth" // {
          default = true;
        };

        permitRootLogin = lib.mkOption {
          type = lib.types.enum [
            "no"
            "prohibit-password"
            "yes"
          ];
          default = "no";
          description = "Whether root can SSH in. Default 'no' — use sudo or a regular user.";
        };

        ports = lib.mkOption {
          type = lib.types.listOf lib.types.port;
          default = [ 22 ];
        };

        extraConfig = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Extra OpenSSH settings merged into services.openssh.settings.";
        };
      };

      config = lib.mkIf cfg.enable {
        # Keep the client agent available for both interactive and headless
        # users.  The agent is a per-user systemd service; it does not change
        # how this host's SSH server authenticates inbound connections.
        programs.ssh = {
          startAgent = true;
          extraConfig = "AddKeysToAgent yes";
        };
        services.gnome.gcr-ssh-agent.enable = false;

        services.openssh = {
          enable = true;
          settings = {
            PasswordAuthentication = false;
            KbdInteractiveAuthentication = false;
            PermitRootLogin = cfg.permitRootLogin;
          }
          // cfg.extraConfig;
          inherit (cfg) ports;
        };
      };
    };
}
