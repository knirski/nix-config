# Common args for `import nixpkgs { ... }`. Centralizes allowUnfree and the
# command-code overlay so it can't drift between NixOS, darwin, and standalone
# HM host assemblers.
#
# allowUnfree stays global and unconditional on every host: it's a licensing
# acknowledgment, not a security boundary, and per-host scoping would add
# complexity for no real benefit (repo owner decision, task S4).
#
# permittedInsecurePackages is intentionally NOT hardcoded here: unlike
# allowUnfree, it used to apply unconditionally to every host,
# including soyo (a headless appliance with no bitwarden-desktop/Electron
# consumer -- see lib/insecure-package-exceptions.nix for how this was
# verified). Callers that actually need an exception pass one explicitly.
# Omitting the argument means the returned config carries no
# permittedInsecurePackages key at all, so modules/nixos/base.nix's and
# modules/darwin/base.nix's `nixpkgs.config = sharedNixpkgsArgs.config;`
# (shared by soyo too) never collides with a workstation host's own,
# separate `nixpkgs.config.permittedInsecurePackages = [...]` module
# definition: the two attrsets touch disjoint keys, so the module system's
# recursiveUpdate-based merge of `nixpkgs.config` is unambiguous regardless
# of definition order (verified via `nix eval` against the real host
# outputs -- see the task S4 report).
#
# Usage:
#   pkgs = import inputs.nixpkgs-unstable
#     ((import ../../lib/mk-nixpkgs-args.nix {}) // { system = "x86_64-linux"; });
#   pkgs = import inputs.nixpkgs-unstable
#     ((import ../../lib/mk-nixpkgs-args.nix {
#       permittedInsecurePackages = map (e: e.package) (import ./insecure-package-exceptions.nix);
#     }) // { system = "x86_64-linux"; });
{
  permittedInsecurePackages ? [ ],
}:
{
  config = {
    allowUnfree = true;
  }
  // (if permittedInsecurePackages == [ ] then { } else { inherit permittedInsecurePackages; });
  overlays = [
    (final: _: {
      command-code = final.callPackage ../modules/_pkgs/command-code.nix { };
      command-code-desktop = final.callPackage ../modules/_pkgs/command-code-desktop.nix { };
      rtk = final.callPackage ../modules/_pkgs/rtk.nix { };
    })

  ];
}
