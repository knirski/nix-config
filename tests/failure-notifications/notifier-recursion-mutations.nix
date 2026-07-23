# Negative fixtures for the "ntfy-failure@ cannot recurse through its own
# OnFailure" invariant in modules/parts/failure-notification-checks.nix.
#
# The safe fixture is an empty unitConfig (no OnFailure key at all). Each
# mutation adds one, which the guard must reject regardless of the target —
# even a non-recursive target is still wrong, because the brief's contract is
# "the notification template must never itself carry OnFailure".
[
  {
    name = "notifier-gains-self-onfailure";
    mutate = unitConfig: unitConfig // { OnFailure = "ntfy-failure@%N.service"; };
  }
  {
    name = "notifier-gains-onfailure-to-other-unit";
    mutate = unitConfig: unitConfig // { OnFailure = "some-other.service"; };
  }
]
