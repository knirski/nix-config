{
  aspects.nixos.power-profiles = { lib, ... }: {
    # power-profiles-daemon is a lightweight sysfs service that doesn't need
    # the display manager. Use unitConfig.After with empty-string reset to
    # fully replace the upstream After= (drop-in semantics are additive for
    # list directives), and pull in via multi-user.target instead of
    # graphical.target so it starts ~1m42s earlier.
    systemd.services.power-profiles-daemon = {
      unitConfig = {
        After = lib.mkForce [
          ""
          "multi-user.target"
        ];
      };
      wantedBy = lib.mkForce [ "multi-user.target" ];
    };
  };
}
