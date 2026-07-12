# Named mutation: the negative derivation must fail the focused assertion in
# require-early-persist.nix.  This is never imported by a production host.
{ lib, ... }:
{
  fileSystems."/persist" = {
    neededForBoot = lib.mkForce false;
    options = lib.mkForce [ "subvol=persist" ];
  };
}
