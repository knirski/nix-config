# NixOS aspect: Rust toolchain, Cargo package manager, and LSP.
#
# A general-purpose development runtime that can power anything from desktop
# tooling (language servers, build toolchains) to CLI utilities. Toggle it
# independently per host rather than bundling with any role aspect.
{
  aspects.nixos.rust = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      cargo
      rust-analyzer
      rustc
    ];
  };
}
