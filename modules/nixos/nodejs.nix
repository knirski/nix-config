# NixOS aspect: Node.js runtime and package managers.
#
# A general-purpose runtime that can power anything from desktop tooling
# (npx skills, language servers, build toolchains) to server backends.
# Toggle it independently per host rather than bundling with any role aspect.
{
  aspects.nixos.nodejs = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      bun
      nodejs
      pnpm
      yarn
    ];
  };
}
