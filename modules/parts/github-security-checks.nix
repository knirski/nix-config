# flake-parts module: keep workflow trust boundaries executable. actionlint
# validates syntax; this check enforces immutable actions and token policy.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      python = pkgs.python3.withPackages (packages: [ packages.pyyaml ]);
    in
    {
      checks.github-workflow-policy = pkgs.runCommand "github-workflow-policy" { } ''
        checker=${inputs.self}/tests/github-workflows/check_workflows.py
        fixtures=${inputs.self}/tests/github-workflows/fixtures

        ${python}/bin/python "$checker" ${inputs.self}/.github/workflows/*.yml
        ${python}/bin/python "$checker" "$fixtures/pass.yml"

        for rejected in "$fixtures"/reject-*.yml; do
          if ${python}/bin/python "$checker" "$rejected" >stdout 2>stderr; then
            echo "error: workflow-policy fixture unexpectedly passed: $rejected" >&2
            exit 1
          fi
          if [[ ! -s stderr ]]; then
            echo "error: fixture did not produce an actionable policy error: $rejected" >&2
            exit 1
          fi
        done

        touch "$out"
      '';
    };
}
