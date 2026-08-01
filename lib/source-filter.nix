# Keep Nix-backed repository checks stable when they are evaluated from a
# developer checkout. `path:.` can contain local agent worktrees and settings
# that are intentionally ignored by Git but would otherwise enter
# `cleanSource` and affect linting or documentation checks. This is a
# deliberately bounded checkout-artifact filter, not a claim that pure Nix can
# discover Git's tracked-file index.
{ lib }:
src:
lib.cleanSourceWith {
  inherit src;
  filter =
    path: type:
    let
      root = toString src;
      value = toString path;
      prefix = "${root}/";
      relative = if lib.hasPrefix prefix value then lib.removePrefix prefix value else "";
      excluded = [
        ".git"
        ".claude"
        ".commandcode/settings.json"
        ".direnv"
        ".mypy_cache"
        ".pytest_cache"
        ".ruff_cache"
        "result"
      ];
      isExcluded = item: relative == item || lib.hasPrefix "${item}/" relative;
    in
    lib.cleanSourceFilter path type && !(builtins.any isExcluded excluded);
}
