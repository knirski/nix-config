# flake-parts module: keep the sanitized public overview reproducible.
{
  inputs,
  ...
}:
{
  perSystem =
    {
      config,
      pkgs,
      ...
    }:
    {
      checks.topology-freshness = pkgs.runCommand "topology-freshness" { } ''
        generated=${config.packages.topology-public-overview}/overview.svg
        committed=${inputs.self}/docs/topology/overview.svg

        if ! cmp --silent "$generated" "$committed"; then
          echo "error: docs/topology/overview.svg is stale" >&2
          echo "regenerate with: just topology" >&2
          exit 1
        fi

        touch "$out"
      '';
    };
}
