{
  # M2 maintenance is host policy, not a role-neutral default. The aspect was
  # assembled but its enable option was previously never set, so its documented
  # timers and bounded failure notifications did not exist in the evaluated host.
  lanAppliance.services.maintenance = {
    enable = true;
    # Soyo's alerts go to its own ntfy.sh channel (soyo-alerts-*); the secret
    # names are declared in modules/parts/soyo.nix. Zbook overrides these with
    # its own channel (hosts/zbook/maintenance.nix).
    ntfyTokenSecret = "soyo-ntfy-token";
    ntfyTopicSecret = "soyo-ntfy-topic";
  };
}
