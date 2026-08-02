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
  filter = import ./source-filter-predicate.nix { inherit lib; } src;
}
