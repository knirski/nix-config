# Override of nixpkgs' codex to bump to the latest upstream release (0.144.1).
# The nixpkgs-unstable input (updated 2026-07-05) still has 0.142.5.
# Once nixpkgs-unstable catches up, remove this file and revert the overlay
# in modules/nixos/base.nix to just use `prev.codex`.
{
  prevCodex,
  rustPlatform,
  fetchFromGitHub,
}:
let
  # buildRustPackage accepts either a set or a function (finalAttrs pattern).
  # We wrap it to inject the correct cargoHash for the new version.
  rustPlatform' = rustPlatform // {
    buildRustPackage =
      f:
      rustPlatform.buildRustPackage (
        if builtins.isFunction f then
          self: (f self) // { cargoHash = "sha256-S4dsZXfmKvJItL2XYKyxfhqdCMATEG6oPjrtVRwkuYc="; }
        else
          f // { cargoHash = "sha256-S4dsZXfmKvJItL2XYKyxfhqdCMATEG6oPjrtVRwkuYc="; }
      );
  };
in
(prevCodex.override { rustPlatform = rustPlatform'; }).overrideAttrs (_: {
  version = "0.144.1";
  src = fetchFromGitHub {
    owner = "openai";
    repo = "codex";
    tag = "rust-v0.144.1";
    hash = "sha256-KHgrqIZyAmLhTZSRYbb7huBO8neOib/B1Vx/oPW2nEU=";
  };
})
