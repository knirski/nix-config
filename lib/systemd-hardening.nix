# Conservative profiles for repository-owned helper services. These are not
# applied to upstream daemons blindly: each caller adds only the writable paths
# and address families its documented job requires.
let
  common = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectHome = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectSystem = "strict";
    RestrictNamespaces = true;
    RestrictSUIDSGID = true;
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    RemoveIPC = true;
    SystemCallArchitectures = "native";
    UMask = "0077";
  };
in
{
  offline = common // {
    RestrictAddressFamilies = [ "AF_UNIX" ];
  };
  networkClient = common // {
    RestrictAddressFamilies = [
      "AF_UNIX"
      "AF_INET"
      "AF_INET6"
    ];
  };
}
