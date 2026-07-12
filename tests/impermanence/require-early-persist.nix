# Test-only contract for the early-boot persistence dependency.  Production
# already sets this in the persistence aspect; keeping the mutation fixture here
# lets the negative check prove the contract without weakening a real host.
{ config, ... }:
{
  assertions = [
    {
      assertion = config.fileSystems ? "/persist" && config.fileSystems."/persist".neededForBoot;
      message = "impermanence fixture: /persist must be mounted in the initrd";
    }
  ];
}
