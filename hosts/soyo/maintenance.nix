# M2 maintenance is host policy, not a role-neutral default. The aspect was
# assembled but its enable option was previously never set, so its documented
# timers and bounded failure notifications did not exist in the evaluated host.
{
  lanAppliance.services.maintenance.enable = true;
}
