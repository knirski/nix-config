{ lib }:
src: path: type:
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
  components = lib.splitString "/" relative;
  isExcluded =
    item: relative == item || lib.hasPrefix "${item}/" relative || builtins.elem item components;
in
lib.cleanSourceFilter path type && !(builtins.any isExcluded excluded)
