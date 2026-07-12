# flake-parts module: enforce the narrow policy for artifacts promoted as
# public-facing overviews. Precise host data and operator runbooks are not input
# to this check: their private addresses are intentional declarative facts, not
# credentials. See docs/security/public-repository.md.
{ inputs, ... }:
{
  perSystem =
    { config, pkgs, ... }:
    {
      checks.public-repository-data = pkgs.runCommand "public-repository-data" { } ''
        checker=${inputs.self}/tests/public-repository/check_public_artifact.py
        fixtures=${inputs.self}/tests/public-repository/fixtures

        # Validate both the policy fixture and the actual generated artifact.
        ${pkgs.python3}/bin/python "$checker" "$fixtures/public-overview.svg"
        ${pkgs.python3}/bin/python "$checker" ${config.packages.topology-public-overview}/overview.svg

        expected_reason() {
          case "$1" in
            reject-active-content.svg) echo 'unapproved <script> element' ;;
            reject-attribute-metadata.svg) echo "unapproved value for attribute 'id'" ;;
            reject-dimensions.svg) echo 'dimensions exceed' ;;
            reject-event-handler.svg) echo 'event-handler attribute' ;;
            reject-excessive-bytes.svg) echo 'exceeds 4096-byte size limit' ;;
            reject-external-style.svg) echo 'unapproved <style> element' ;;
            reject-external-url.svg) echo 'external resource reference' ;;
            reject-interface.svg) echo 'prohibited network interface' ;;
            reject-ip.svg) echo 'prohibited IPv4 address' ;;
            reject-known-device.svg) echo 'prohibited known LAN device label' ;;
            reject-mac.svg) echo 'prohibited MAC address' ;;
            reject-non-text-content.svg) echo 'text in non-text element' ;;
            reject-unknown-label.svg) echo 'text outside the public vocabulary' ;;
            *) echo "error: fixture lacks an expected diagnostic: $1" >&2; return 1 ;;
          esac
        }

        for rejected in "$fixtures"/reject-*.svg; do
          if ${pkgs.python3}/bin/python "$checker" "$rejected" >check.stdout 2>check.stderr; then
            echo "error: negative public-data fixture unexpectedly passed: $rejected" >&2
            exit 1
          fi
          expected=$(expected_reason "$(basename "$rejected")")
          if ! grep -Fq "$expected" check.stderr; then
            echo "error: fixture did not fail for its intended reason: $rejected" >&2
            echo "expected diagnostic: $expected" >&2
            cat check.stderr >&2
            exit 1
          fi
        done

        touch "$out"
      '';
    };
}
