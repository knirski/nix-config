{
  # This module depends on package overrides in the host assembler:
  #   - cosmic-ext-* packages come from the stable nixpkgs input overlay
  #     (not available in nixpkgs-unstable used as the primary channel).
  # Future hosts toggling this aspect must replicate that overlay.
  aspects.nixos.cosmic =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    {
      services = {
        desktopManager.cosmic.enable = true;
        displayManager.cosmic-greeter.enable = true;
      };

      environment.systemPackages = with pkgs; [
        cosmic-ext-applet-external-monitor-brightness
        cosmic-ext-tweaks
      ];

      # Freeze cosmic-comp before GPU suspend so it releases DRM master.
      # Without this, nvidia-suspend.service blocks trying to take over the
      # DRM device while cosmic-comp still holds it, causing a 60s user.slice
      # freeze timeout and broken display state after resume.
      # SIGSTOP is the standard Wayland compositor suspend pattern — it
      # prevents any DRM ioctl from being in-flight when the GPU suspends.
      powerManagement.powerDownCommands = lib.mkIf config.workstation.nvidiaConfig.enable ''
        PID=$(pidof cosmic-comp 2>/dev/null || true)
        if [ -n "$PID" ]; then
          kill -STOP "$PID" 2>/dev/null || true
        fi
      '';

      # Unfreeze cosmic-comp as part of nvidia-resume's ExecStartPost, so
      # the SIGCONT runs immediately after nvidia-sleep.sh 'resume' finishes
      # restoring GPU state. This avoids the ordering problem with sleep-actions
      # ExecStop (resumeCommands) running in parallel with nvidia-resume.
      systemd.services.nvidia-resume = lib.mkIf config.workstation.nvidiaConfig.enable {
        serviceConfig.ExecStartPost = [ "" (
          pkgs.writeShellScript "resume-cosmic-comp" ''
            set -e
            PID=$(pidof cosmic-comp 2>/dev/null || true)
            if [ -n "$PID" ]; then
              kill -CONT "$PID" 2>/dev/null || true
            fi
          ''
        ) ];
      };

      # After resume, unfreeze cosmic-comp (via nvidia-resume ExecStartPost above)
      # and re-probe external displays.
      # This finds all connected external monitors on the NVIDIA card (card0),
      # waits up to 10s for them to re-detect, then triggers a udev `change`
      # event on each — the same uevent the kernel sends on physical hotplug.
      # cosmic-comp already listens for these and re-probes display state
      # without needing to restart the compositor.
      powerManagement.resumeCommands = lib.mkIf config.workstation.nvidiaConfig.enable ''
        # Find all external connectors on the NVIDIA card (card0) and their
        # current status. Skips internal panels (eDP, LVDS).
        CONNECTORS=""
        HAD_DISCONNECTED=false
        for connector in /sys/class/drm/card0-*/status; do
          [ -f "$connector" ] || continue
          name=$(basename "$(dirname "$connector")")
          case "$name" in
            card0-eDP-*|card0-LVDS-*) continue ;;
          esac
          dir="$(dirname "$connector")"
          CONNECTORS="$CONNECTORS $dir"
          if [ "$(cat "$connector" 2>/dev/null)" != "connected" ]; then
            HAD_DISCONNECTED=:
          fi
        done

        # If any external connector was disconnected, poll all of them
        # for up to 10s total for the GPU and dock to re-enumerate.
        if $HAD_DISCONNECTED 2>/dev/null; then
          for i in $(${pkgs.coreutils}/bin/seq 1 10); do
            ALL=true
            for dir in $CONNECTORS; do
              if [ "$(cat "$dir/status" 2>/dev/null)" != "connected" ]; then
                ALL=false
              fi
            done
            $ALL && break
            ${pkgs.coreutils}/bin/sleep 1
          done
        fi

        # Trigger a udev 'change' event on each NVIDIA connector to
        # simulate a hotplug uevent. cosmic-comp re-probes display state
        # when it receives these.
        for dir in $CONNECTORS; do
          ${pkgs.systemd}/bin/udevadm trigger --action=change "$dir" 2>/dev/null || true
        done
      '';
    };
}
