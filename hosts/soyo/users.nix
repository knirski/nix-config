{ config, ... }:
{
  users.users.root.hashedPasswordFile = config.age.secrets.root-password.path;

  users.users.krzysiek = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPasswordFile = config.age.secrets.krzysiek-password.path;
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../../secrets/krzysiek-authorized-key.pub)
      (builtins.readFile ../../secrets/soyo-authorized-key.pub)
    ];
  };
}
