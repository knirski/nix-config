{
  aspects.nixos.laptop = _: {
    services = {
      power-profiles-daemon.enable = true;
      thermald.enable = true;
      upower.enable = true;
      fwupd.enable = true;
    };

    # CPU frequency scaling governor (powersave by default on battery)
    powerManagement.cpuFreqGovernor = "powersave";
    powerManagement.powertop.enable = true;

    # Intel P-State driver (better power management on 12th/13th gen)
    boot.kernelParams = [ "intel_pstate=active" ];

    # Laptop lid switch handling
    services.logind.settings.Login = {
      HandleLidSwitch = "suspend";
      HandleLidSwitchExternalPower = "lock";
      HandleLidSwitchDocked = "ignore";
    };
  };
}
