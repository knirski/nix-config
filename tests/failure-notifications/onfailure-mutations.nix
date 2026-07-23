# Negative fixtures for the "reviewed operational unit has the crash-notify
# edge" invariant in modules/parts/failure-notification-checks.nix.
#
# Each mutation starts from a unitConfig that satisfies the contract
# (OnFailure = "ntfy-failure@%N.service") and breaks it one way. None of
# these should ever validate as correct — mirrors the shape of
# tests/systemd-hardening/mutations.nix.
[
  {
    name = "removes-onfailure";
    mutate = unitConfig: builtins.removeAttrs unitConfig [ "OnFailure" ];
  }
  {
    name = "points-to-unrelated-service";
    # A plausible copy-paste mistake: the unit fires OnFailure, but at
    # something that isn't the shared notification template at all.
    mutate = unitConfig: unitConfig // { OnFailure = "some-other.service"; };
  }
  {
    name = "drops-the-percent-n-specifier";
    # Without %N, every failing unit's notification would report the same
    # (wrong) identity instead of "%N" expanding to the actual failing unit.
    mutate = unitConfig: unitConfig // { OnFailure = "ntfy-failure@.service"; };
  }
  {
    name = "sets-onfailure-to-empty-string";
    mutate = unitConfig: unitConfig // { OnFailure = ""; };
  }
]
