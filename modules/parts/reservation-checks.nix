# Pure evaluation tests for the Soyo reservation schema. These catch invalid
# inventory before it can become DHCP leases or local DNS records.
_: {
  perSystem =
    { pkgs, ... }:
    let
      networkPolicy = import ../../hosts/soyo/network-policy.nix;
      validate =
        reservations:
        import ../../lib/network/validate-reservations.nix {
          inherit reservations;
          inherit (networkPolicy) subnetPrefix dynamicPool;
        };

      base = [
        {
          name = "host-a";
          mac = "00:11:22:33:44:aa";
          ip = "10.0.0.10";
        }
        {
          name = "host-b";
          mac = "00:11:22:33:44:66";
          ip = "10.0.0.11";
        }
      ];

      accepted = reservations: (builtins.tryEval (builtins.deepSeq (validate reservations) true)).success;
      rejected = reservations: !accepted reservations;

      testResults = {
        production-inventory = accepted (import ../../hosts/soyo/reservations.nix);
        valid-inventory = accepted base;
        multihomed-name = accepted [
          (builtins.head base)
          (
            (builtins.head base)
            // {
              mac = "00:11:22:33:44:77";
              ip = "10.0.0.12";
            }
          )
        ];
        duplicate-mac-case-insensitive = rejected (
          base
          ++ [
            {
              name = "host-c";
              mac = "00:11:22:33:44:AA";
              ip = "10.0.0.12";
            }
          ]
        );
        duplicate-ip = rejected (
          base
          ++ [
            {
              name = "host-c";
              mac = "00:11:22:33:44:77";
              ip = "10.0.0.10";
            }
          ]
        );
        malformed-mac = rejected [ ((builtins.head base) // { mac = "not-a-mac"; }) ];
        malformed-ipv4 = rejected [ ((builtins.head base) // { ip = "10.0.0.999"; }) ];
        invalid-dns-label = rejected [ ((builtins.head base) // { name = "Host_A"; }) ];
        outside-subnet = rejected [ ((builtins.head base) // { ip = "10.0.1.10"; }) ];
        network-address = rejected [ ((builtins.head base) // { ip = "10.0.0.0"; }) ];
        broadcast-address = rejected [ ((builtins.head base) // { ip = "10.0.0.255"; }) ];
        dynamic-pool-overlap = rejected [ ((builtins.head base) // { ip = "10.0.0.50"; }) ];
        non-attribute-entry = rejected [ "not-an-attribute-set" ];
        missing-field = rejected [ (builtins.removeAttrs (builtins.head base) [ "mac" ]) ];
        non-string-field = rejected [ ((builtins.head base) // { ip = 10; }) ];
      };

      failed = builtins.attrNames (pkgs.lib.filterAttrs (_: passed: !passed) testResults);
    in
    {
      checks.reservation-validation =
        assert
          failed == [ ]
          || throw "Reservation validation tests failed: ${builtins.concatStringsSep ", " failed}";
        pkgs.runCommand "reservation-validation-test" { } ''
          touch $out
        '';
    };
}
