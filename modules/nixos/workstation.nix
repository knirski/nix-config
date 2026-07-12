# Workstation role aspect.
#
# All sub-features (OpenSSH, Tailscale, backup) were extracted to shared
# aspects (ssh.nix, tailscale.nix, backup.nix). Toggle those separately
# in the host assembler.
#
# The role marker gives host-agnostic tooling a stable way to select checks;
# all workstation sub-features remain separate opt-in aspects.
{
  aspects.nixos.workstation = {
    environment.etc."nix-config/role".text = "workstation\n";
  };
}
