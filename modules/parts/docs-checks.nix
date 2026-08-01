# Documentation correctness is an offline build contract. External HTTP links
# are intentionally ignored here so ordinary checks never depend on the public
# network; scheduled link monitoring can report upstream outages separately.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      sourceFilter = import ../../lib/source-filter.nix { inherit (pkgs) lib; };
      source = sourceFilter inputs.self;
      docsCheck = pkgs.writeShellApplication {
        name = "docs-check";
        runtimeInputs = [ pkgs.python3 ];
        text = ''
          exec python3 ${../../tests/docs/check_docs.py} "$@"
        '';
      };
    in
    {
      packages.docs-check = docsCheck;
      apps.docs-check = {
        type = "app";
        program = "${docsCheck}/bin/docs-check";
        meta.description = "Validate local documentation links, lifecycle status, and discoverability";
      };
      checks.docs-correctness =
        pkgs.runCommand "docs-correctness" { nativeBuildInputs = [ docsCheck ]; }
          ''
            cp -R ${source} source
            chmod -R u+w source
            docs-check --repo source --self-test
            touch "$out"
          '';
    };
}
