# Aspect: command-code — installs the Command Code CLI system-wide and
# exposes the GITHUB_TOKEN agenix secret for authenticated gh/git pushes.
#
# The `cmd` CLI tool (and its aliases `command-code`, `commandcode`)
# is added to environment.systemPackages. The `github-token` agenix
# secret is declared in modules/nixos/users.nix and decrypted at boot.
# extraInit sources it so gh and git (HTTPS remote) can authenticate
# without interactive prompts.
{ config, pkgs, ... }:
{
  aspects.nixos.commandCode = {
    environment.systemPackages = with pkgs; [
      command-code
    ];

    environment.extraInit = ''
        if [ -r "${config.age.secrets.github-token.path}" ]; then
          export GITHUB_TOKEN="$(cat "${config.age.secrets.github-token.path}")"
          export GH_TOKEN="$GITHUB_TOKEN"
        fi
      '';
  };
}
