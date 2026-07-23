# Negative fixtures for the tailscale-auth -> tailscaled dependency contract
# (see modules/parts/systemd-hardening-checks.nix, tailscaleDependencyValid).
#
# Each mutation starts from a fixture that satisfies the contract and breaks
# exactly one aspect of it. None of these should ever validate as correct.
[
  {
    name = "misspelled-tailscale-unit";
    # The historical bug: referencing a unit that services.tailscale.enable
    # never creates. Proves the check fails for the right reason (the
    # dependency string is wrong), not merely because some field is missing.
    mutate =
      deps:
      deps
      // {
        after = [
          "tailscale.service"
          "agenix-activation.service"
        ];
        wants = [ "tailscale.service" ];
      };
  }
  {
    name = "missing-agenix-activation-after";
    mutate =
      deps:
      deps
      // {
        after = [ "tailscaled.service" ];
      };
  }
  {
    name = "missing-wants";
    mutate =
      deps:
      deps
      // {
        wants = [ ];
      };
  }
  {
    name = "tailscaled-service-not-evaluated";
    # Guards against the check degrading back into pure string matching: even
    # if after/wants look right, the referenced unit must actually exist in
    # the evaluated service set.
    mutate =
      deps:
      deps
      // {
        tailscaledExists = false;
      };
  }
]
