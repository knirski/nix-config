# Workstation role aspect.
#
# All sub-features (OpenSSH, Tailscale, backup) were extracted to shared
# aspects (ssh.nix, tailscale.nix, backup.nix). Toggle those separately
# in the host assembler.
#
# Kept as empty semantic marker so the assembler's `workstation` reference
# still works and clearly says "this is a workstation" even though all
# sub-features are now their own aspects.
_: {
  aspects.nixos.workstation = { };
}
