# Aspect: command-code — installs the Command Code CLI system-wide.
#
# Adds the `cmd` CLI tool (and its aliases `command-code`, `commandcode`)
# to environment.systemPackages, making them available to every user on
# the host. The package is defined in modules/pkgs/command-code.nix and
# built with buildNpmPackage from the npm tarball.
{ pkgs, ... }:
{
  aspects.nixos.commandCode = {
    environment.systemPackages = with pkgs; [
      command-code
    ];
  };
}
