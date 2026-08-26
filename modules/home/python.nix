# Home Manager aspect: Python 3 runtime and uv package manager.
#
# Keep this separate from the base and development aspects so the runtime is
# available to every host without making either shared aspect responsible for
# a particular role. The NixOS counterpart also installs these packages
# system-wide for hosts that need them outside the operator's home profile.
# uv's NixOS guidance recommends using the packaged interpreter and disabling
# downloads of dynamically linked Python builds:
# https://github.com/NixOS/nixpkgs/blob/master/doc/packages/uv.section.md
{
  aspects.homeManager.python =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        python3
        uv
      ];

      home.sessionVariables = {
        UV_PYTHON = "${pkgs.python3}/bin/python";
        UV_PYTHON_DOWNLOADS = "never";
      };
    };
}
