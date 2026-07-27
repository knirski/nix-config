# NixOS aspect: Python 3 runtime and uv package manager.
#
# A general-purpose runtime that can power anything from desktop tooling
# (language servers, linting) to server backends. Toggle it independently
# per host rather than bundling with any role aspect.
#
# uv, by default, fetches dynamically-linked Python executables that won't
# run on NixOS.  The environment variables below pin it to the system
# Python and forbid downloads -- see nixpkgs docs for details:
#   https://github.com/NixOS/nixpkgs/blob/master/doc/packages/uv.section.md
{
  aspects.nixos.python = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      python3
      uv
    ];

    environment.sessionVariables = {
      UV_PYTHON = "${pkgs.python3}/bin/python";
      UV_PYTHON_DOWNLOADS = "never";
    };
  };
}
