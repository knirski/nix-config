{
  lanAppliance.services.remoteUnlock = {
    enable = true;
    interface = "enp1s0";
    lanAddress = "10.0.0.9/24";
    rescueAddress = "192.168.254.2/30";
    gatewayAddress = "10.0.0.1";
    sshHostKeys = [ "/boot/initrd-ssh/ssh_host_ed25519_key" ];
    authorizedKeys = [
      (builtins.readFile ../../secrets/krzysiek-authorized-key.pub)
    ];
  };
}
