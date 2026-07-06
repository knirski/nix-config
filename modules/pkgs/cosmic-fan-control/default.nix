{
  rustPlatform,
  fetchFromGitHub,
  lib,
}:
rustPlatform.buildRustPackage rec {
  pname = "cosmic-fan-control";
  version = "26.01";

  src = fetchFromGitHub {
    owner = "wiiznokes";
    repo = "fan-control";
    rev = "3668e5e64722e7029639454a5f84d3e913f91657";
    hash = "sha256-k8s4DM02iC4pZhIY6P3/w4eMWXAMOe6w+20PDRL65qE=";
  };

  # Build with lib.fakeHash first to discover the real hash:
  #   nix build .#nixpkgs-unstable#cosmic-fan-control 2>&1 | grep "got:"
  # Then replace lib.fakeHash with the printed SRI hash.
  cargoHash = lib.fakeHash;

  meta = with lib; {
    description = "Control your fans with different behaviors";
    homepage = "https://github.com/wiiznokes/fan-control";
    license = licenses.mit;
    mainProgram = "cosmic-fan-control";
    platforms = platforms.linux;
  };
}
