# Reviewed registry of `permittedInsecurePackages` exceptions. Single source
# of truth for two consumers that must never drift apart:
#
#   - modules/parts/zbook.nix, modules/parts/macbook.nix,
#     modules/parts/ubuntu.nix (the "workstation" hosts that enable
#     aspects.homeManager.desktop) wire `map (e: e.package) entries` into
#     their own nixpkgs.config.permittedInsecurePackages -- soyo (a headless
#     appliance that never enables the desktop aspect) intentionally does
#     not import this file at all, so it carries no insecure-package
#     allowance.
#   - modules/parts/nixpkgs-policy-checks.nix, which rejects any entry here
#     missing the required rationale/owner/review metadata below, and proves
#     (via a real `nix eval` against nixosConfigurations.soyo) that soyo's
#     evaluated nixpkgs.config never picks any of this up.
#
# Every entry MUST carry:
#   package             - the exact permittedInsecurePackages string
#                         ("<pname>-<version>") nixpkgs expects.
#   knownVulnerability  - the reason nixpkgs' own `meta.knownVulnerabilities`
#                         flags this package (kept in sync by hand; verify
#                         with e.g.
#                         `nix eval .#nixosConfigurations.zbook.pkgs.<pkg>.meta.knownVulnerabilities`).
#   rationale           - why this repository still needs the package despite
#                         the flag, and which real package in this flake
#                         consumes it (checked, not assumed -- see the S4
#                         task report for how this was verified).
#   owner               - who is accountable for revisiting this exception.
#   reviewed            - ISO-8601 date this entry was last confirmed still
#                         necessary.
#   reviewIntervalDays  - how long the `reviewed` date should be considered
#                         current before a human should re-confirm it.
[
  {
    package = "electron-39.8.10";
    knownVulnerability = "Electron version 39.8.10 is EOL";
    rationale = ''
      bitwarden-desktop (installed by aspects.homeManager.desktop on Linux
      hosts only, see modules/home/desktop.nix) depends on electron_39 --
      nixpkgs' bitwarden-desktop package.nix sets `electron = electron_39;`
      -- which resolves to electron-39.8.10. nixpkgs marks that release
      insecure only because the 39.x line is end-of-life upstream, not
      because of a bitwarden-specific CVE.

      Verified via `nix eval` on 2026-07-23: removing this exception makes
      both `nixosConfigurations.zbook.config.system.build.toplevel` and
      `homeConfigurations.ubuntu.activationPackage` fail evaluation, naming
      exactly "electron-39.8.10" as the insecure package -- confirming
      bitwarden-desktop (not antigravity-cli, which is a statically-fetched
      Go binary with no Electron dependency) is the actual consumer, and
      that no other package in any host's closure needs an insecure-package
      allowance.
    '';
    owner = "krzysiek (repo owner)";
    reviewed = "2026-07-23";
    reviewIntervalDays = 180;
  }
]
