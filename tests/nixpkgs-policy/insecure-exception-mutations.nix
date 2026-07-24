# Negative fixtures for the insecure-package exception schema enforced by
# modules/parts/nixpkgs-policy-checks.nix (insecureExceptionValid). Each
# mutation starts from a fixture that satisfies the schema and breaks it one
# way. None of these should ever validate as correct — mirrors the shape of
# tests/failure-notifications/onfailure-mutations.nix and
# tests/observability/btrfs-metric-contract-mutations.nix.
[
  {
    name = "missing-package-field";
    mutate = entry: builtins.removeAttrs entry [ "package" ];
  }
  {
    name = "missing-known-vulnerability-field";
    mutate = entry: builtins.removeAttrs entry [ "knownVulnerability" ];
  }
  {
    name = "missing-rationale-field";
    mutate = entry: builtins.removeAttrs entry [ "rationale" ];
  }
  {
    name = "missing-owner-field";
    mutate = entry: builtins.removeAttrs entry [ "owner" ];
  }
  {
    name = "missing-reviewed-field";
    mutate = entry: builtins.removeAttrs entry [ "reviewed" ];
  }
  {
    name = "missing-review-interval-field";
    mutate = entry: builtins.removeAttrs entry [ "reviewIntervalDays" ];
  }
  {
    name = "empty-package-string";
    mutate = entry: entry // { package = ""; };
  }
  {
    name = "empty-rationale-string";
    mutate = entry: entry // { rationale = ""; };
  }
  {
    name = "empty-owner-string";
    mutate = entry: entry // { owner = ""; };
  }
  {
    name = "malformed-reviewed-date";
    # Not ISO-8601 (YYYY-MM-DD) — the classic "07/23/2026" copy-paste mistake.
    mutate = entry: entry // { reviewed = "07/23/2026"; };
  }
  {
    name = "non-string-reviewed-date";
    mutate = entry: entry // { reviewed = 20260723; };
  }
  {
    name = "zero-review-interval";
    mutate = entry: entry // { reviewIntervalDays = 0; };
  }
  {
    name = "negative-review-interval";
    mutate = entry: entry // { reviewIntervalDays = -30; };
  }
  {
    name = "non-integer-review-interval";
    mutate = entry: entry // { reviewIntervalDays = "180"; };
  }
]
