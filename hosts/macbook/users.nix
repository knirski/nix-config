# macOS user definition for the macbook host.
_: {
  users.users.krzysiek = {
    name = "krzysiek";
    home = "/Users/krzysiek";
    # shell intentionally omitted — system zsh via programs.zsh.enable in
    # darwin/base.nix avoids a hard dependency on the Nix store for login.
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../../secrets/krzysiek-authorized-key.pub)
    ];
  };
}
