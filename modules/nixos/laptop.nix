{
  aspects.nixos.laptop =
    { lib, pkgs, ... }:
    {
      services = {
        power-profiles-daemon.enable = true;
        thermald.enable = true;
        upower.enable = true;
        fwupd.enable = true;
      };

      # When the Thunderbolt dock is unplugged and reconnected, the RTL8153
      # Ethernet interface gets a new USB path. NetworkManager may not
      # properly re-match its connection profile or re-evaluate routing/DNS,
      # leaving the system with "connected" but no usable data path.
      #
      # This dispatcher script fires on any "up" event for physical ethernet
      # interfaces (en*) and reloads NM profiles + flushes DNS — same fix
      # as the s2idle resumeCommands below, but triggered on hotplug too.
      networking.networkmanager.dispatcherScripts = [
        {
          source = pkgs.writeShellScript "nm-dock-hotplug-fix" ''
            if [ "$2" = "up" ] && [[ "$1" == en* ]]; then
              ${pkgs.networkmanager}/bin/nmcli connection reload 2>/dev/null || true
              ${pkgs.systemd}/bin/resolvectl flush-caches 2>/dev/null || true
            fi
          '';
          type = "basic";
        }
      ];

      # CPU frequency governor is managed dynamically by power-profiles-daemon
      # (controlled by DMS power profile settings), not hardcoded here.
      # Powertop applies power-saving tunings at boot via --auto-tune;
      # Logitech receiver USB autosuspend is handled immutably via usbcore.quirks.
      powerManagement = {
        powertop.enable = true;
        # After s2idle resume, NetworkManager often reports "connected" but
        # the actual data path (DNS resolution, interface state, route table)
        # is broken — common with USB-C dock Ethernet and s2idle on laptops.
        #
        # Previously this restarted NetworkManager entirely, but DMS (Dank
        # Material Shell) connects to NM via D-Bus and has no reconnection
        # logic — once NM restarts, DMS's signal subscriptions are permanently
        # lost and it shows "not connected" even when WiFi is working.
        # Instead, reload NM connections and flush DNS, which is sufficient
        # to fix the stale data path without breaking D-Bus consumers.
        resumeCommands = ''
          ${pkgs.networkmanager}/bin/nmcli connection reload 2>/dev/null || true
          ${pkgs.systemd}/bin/resolvectl flush-caches 2>/dev/null || true
        '';
      };

      # Intel P-State driver (better power management on 12th/13th gen)
      boot.kernelParams = [
        "intel_pstate=active"
        # Disable USB autosuspend for Logitech Unifying (c52b) and Bolt (c532)
        # receivers at the USB core level, before powertop or udev can touch
        # it. The "b" flag prevents the USB core from ever autosuspending the
        # device — immutable, immune to powertop --auto-tune.
        # https://docs.kernel.org/admin-guide/kernel-parameters.html
        "usbcore.quirks=046d:c52b:b,046d:c532:b"
      ];

      # Laptop lid switch handling
      services.logind.settings.Login = {
        HandleLidSwitch = "suspend";
        HandleLidSwitchExternalPower = "lock";
        HandleLidSwitchDocked = "ignore";
      };

      # Disable USB wake for the dock's Realtek RTL8153 Ethernet adapter.
      # On s2idle (S0ix), link-state changes from the >1Gbps LAN chip
      # trigger an immediate re-wake after suspend entry, even when the
      # cable is idle. Only the dock LAN is targeted, not internal USB.
      services.udev.extraRules = lib.mkAfter ''
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="8153", ATTR{power/wakeup}="disabled"
      '';

      # Disable Thunderbolt host controller and DMA wake sources before every
      # suspend. /proc/acpi/wakeup is a toggle — writing a device name
      # switches it on/off — so we only write if currently enabled.
      # On s2idle, the HP Thunderbolt dock (TDM0/TDM1) fires an immediate
      # wake event on suspend entry, overriding the RTL8153 udev fix.
      systemd.services.disable-thunderbolt-wake = {
        description = "Disable Thunderbolt wake sources before suspend";
        before = [ "systemd-suspend.service" ];
        wantedBy = [ "sleep.target" ];
        serviceConfig.Type = "oneshot";
        script = ''
          for dev in TXHC TDM0 TDM1; do
            if grep -q "^''${dev}[[:space:]]\+S[0-9][[:space:]]\+\*enabled" /proc/acpi/wakeup; then
              echo "$dev" > /proc/acpi/wakeup
            fi
          done
        '';
      };
    };
}
