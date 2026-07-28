{
  aspects.nixos.power-profiles = { lib, ... }: {
    # power-profiles-daemon is a lightweight sysfs service that doesn't need
    # the display manager or the full graphical target. Ordering it after
    # dbus.service (it is Type=dbus) with an empty-string reset avoids a
    # systemd ordering cycle that occurs when a WantedBy= target also
    # appears in After=.
    systemd.services.power-profiles-daemon = {
      unitConfig = {
        After = lib.mkForce [
          ""
          "dbus.service"
        ];
      };
      wantedBy = lib.mkForce [ "multi-user.target" ];
    };
  };
}
