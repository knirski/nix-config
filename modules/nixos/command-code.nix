# Aspect: command-code — exposes the GITHUB_TOKEN agenix secret for
# authenticated gh/git pushes.
#
# The `cmd` CLI tool is installed via Home Manager (modules/home/base.nix).
# The `github-token` agenix secret is declared in modules/nixos/users.nix and
# decrypted at boot. extraInit sources it so gh and git (HTTPS remote) can
# authenticate without interactive prompts.
_: {
  # The github-token agenix secret is declared in modules/nixos/users.nix.
  # Environment variable injection is in modules/home/base.nix (user-scoped).
  aspects.nixos.commandCode = { };
}
