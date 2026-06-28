{
  users.users.krzysiek = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../../secrets/krzysiek-authorized-key.pub)
    ];
  };
}
