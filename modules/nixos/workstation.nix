# Workstation role aspect.
#
# All sub-features (OpenSSH, Tailscale, backup) were extracted to shared
# aspects (ssh.nix, tailscale.nix, backup.nix). Toggle those separately
# in the host assembler.
#
# The role marker gives host-agnostic tooling a stable way to select checks;
# all workstation sub-features remain separate opt-in aspects.
{
  aspects.nixos.workstation = { pkgs, ... }: {
    environment.etc."nix-config/role".text = "workstation\n";

    # Virtualization tools for workstations
    programs.virt-manager.enable = true;
    virtualisation.libvirtd.enable = true;

    environment.systemPackages = with pkgs; [
      distrobox # integrate other distros via containers
    ];
  };
}
