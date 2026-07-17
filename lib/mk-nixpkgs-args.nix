# Common args for `import nixpkgs { ... }`. Centralizes allowUnfree and the
# command-code overlay so they can't drift between NixOS, darwin, and
# standalone HM host assemblers.
#
# Usage:
#   pkgs = import inputs.nixpkgs-unstable
#     ((import ../../lib/mk-nixpkgs-args.nix {}) // { system = "x86_64-linux"; });
_: {
  config = {
    allowUnfree = true;
    permittedInsecurePackages = [
      "electron-39.8.10"
    ];
  };
  overlays = [
    (final: _: {
      command-code = final.callPackage ../modules/_pkgs/command-code.nix { };
      gcx = final.callPackage ../modules/_pkgs/gcx.nix { };
    })
  ];
}
