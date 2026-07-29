# NixOS aspect: Rust toolchain and Cargo package manager.
#
# A general-purpose development runtime that can power anything from desktop
# tooling (language servers, build toolchains) to CLI utilities. Toggle it
# independently per host rather than bundling with any role aspect.
#
# rust-analyzer is intentionally NOT included here — it is installed per-user
# via the homeManager.development aspect (modules/home/development.nix),
# consistent with how all other language servers are managed.
{
  aspects.nixos.rust = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      cargo
      rustc
    ];
  };
}
