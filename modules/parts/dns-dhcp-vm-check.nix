# Packet-level coverage for Soyo's critical DNS services.  The production
# aspects and host policy are reused, while public upstreams and downloaded
# blocklists are replaced with a closed, deterministic VM-only fixture.
{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;
      inherit (config.aspects.nixos) blocky dhcp;
      runKvmTest = import ../../lib/testing/run-kvm-test.nix { inherit pkgs; };
      kvmChecks = import ../../lib/testing/kvm-checks.nix;

      serverAddress = "10.0.0.9";
      reservations = import ../../hosts/soyo/reservations.nix;
      reservationHosts = lib.concatMapStringsSep "\n" (
        reservation: "${reservation.ip} ${reservation.name}.home.arpa ${reservation.name}"
      ) reservations;
    in
    {
      checks.${kvmChecks.dnsDhcpVm} = runKvmTest {
        name = kvmChecks.dnsDhcpVm;
        globalTimeout = 360;

        nodes = {
          server =
            { lib, pkgs, ... }:
            {
              imports = [
                blocky
                dhcp
                ../../hosts/soyo/dns.nix
                ../../hosts/soyo/dhcp.nix
              ];

              virtualisation.vlans = [
                1
                2
              ];
              networking = {
                useDHCP = false;
                # dnsmasq creates lease-aware PTR records only after a client
                # acquires a lease. O1a supplies the same production inventory
                # through /etc/hosts to isolate and prove reverse delegation;
                # O1b is responsible for the real DHCP lease path.
                extraHosts = ''
                  ${reservationHosts}
                  192.0.2.1 example.com
                '';
                interfaces.eth1.ipv4.addresses = [
                  {
                    address = serverAddress;
                    prefixLength = 24;
                  }
                ];
                interfaces.eth2.ipv4.addresses = [
                  {
                    address = "192.0.2.9";
                    prefixLength = 24;
                  }
                ];
              };

              # The production interface is enp1s0. NixOS test VLANs are
              # exposed as eth1, so only the interface-specific wiring changes.
              lanAppliance.services = {
                blocky = {
                  lanInterface = lib.mkForce "eth1";
                  settings = {
                    # These listeners retain production's port ownership but
                    # bind to the VM server address.
                    ports = lib.mkForce {
                      dns = [
                        "127.0.0.1:53"
                        "${serverAddress}:53"
                      ];
                      http = [ "127.0.0.1:4000" ];
                    };

                    # The dedicated fixture node lets the test stop and recover
                    # upstream DNS without ever contacting the internet.
                    upstreams = lib.mkForce {
                      groups.default = [ "192.0.2.53:53" ];
                      timeout = "1s";
                    };
                    bootstrapDns = lib.mkForce [ ];
                    blocking = lib.mkForce {
                      # A multiline string is Blocky's inline-list syntax. A
                      # single-line string would be interpreted as a file path.
                      denylists.vm-test = [
                        ''
                          blocked.test
                        ''
                      ];
                      clientGroupsBlock.default = [ "vm-test" ];
                      blockType = "zeroIp";
                    };
                  };
                };
                dhcp.interface = lib.mkForce "eth1";
              };

              environment.systemPackages = [
                pkgs.iproute2
                pkgs.python3
              ];
            };

          client =
            { pkgs, ... }:
            {
              virtualisation.vlans = [ 1 ];
              networking = {
                useDHCP = false;
                interfaces.eth1.useDHCP = true;
                # NixOS tests put every node name in every node's /etc/hosts.
                # Use a distinct DHCP hostname so dnsmasq can own its lease DNS
                # record instead of rejecting it as an /etc/hosts conflict.
                dhcpcd.extraConfig = "hostname lease-client";
              };
              environment.systemPackages = [
                pkgs.dnsutils
                pkgs.python3
              ];
            };

          upstream = import ../_tests/dns-dhcp/upstream.nix;
        };

        testScript = ''
          start_all()

          for node in (server, client, upstream):
              node.succeed("grep -qw kvm-clock /sys/devices/system/clocksource/clocksource0/available_clocksource")

          server.wait_for_unit("network-online.target")
          server.wait_for_unit("dnsmasq.service")
          server.wait_for_unit("blocky.service")
          upstream.wait_for_unit("dnsmasq.service")

          def status(node, command, expected):
              node.succeed(
                  f"timeout 5s {command} +time=1 +tries=1 +noall +comments "
                  f"| grep -F 'status: {expected}'"
              )

          with subtest("critical daemons own distinct TCP and UDP listeners"):
              server.wait_until_succeeds(
                  "ss -H -lntu 'sport = :53' | grep -F '${serverAddress}:53'"
              )
              server.wait_until_succeeds(
                  "ss -H -lntu 'sport = :5353' | grep -F '${serverAddress}:5353'"
              )
              server.succeed("ss -H -lnup 'sport = :53' | grep -F '\"blocky\"'")
              server.succeed("ss -H -lntp 'sport = :53' | grep -F '\"blocky\"'")
              server.succeed("ss -H -lnup 'sport = :5353' | grep -F '\"dnsmasq\"'")
              server.succeed("ss -H -lntp 'sport = :5353' | grep -F '\"dnsmasq\"'")

          # dnsmasq chooses a stable address from the production dynamic pool,
          # but not necessarily its first address. Capture the real lease and
          # use it for all packet-level assertions below.
          with subtest("real DHCP lease carries the production network policy"):
              client_address = client.wait_until_succeeds(
                  "ip -4 -o address show dev eth1 | sed -n 's/.* inet \\(10\\.0\\.0\\.[0-9]*\\)\\/24.*/\\1/p' | grep ."
              ).strip()
              assert 50 <= int(client_address.rsplit(".", 1)[1]) <= 199
              client.succeed("ip -4 route show default | grep -F 'via 10.0.0.1 dev eth1'")
              client.succeed("grep -Fx 'nameserver ${serverAddress}' /etc/resolv.conf")
              # resolvconf may render a one-item search list with the
              # equivalent resolv.conf `domain` directive.
              client.succeed("grep -Eq '^(search|domain) home\\.arpa$' /etc/resolv.conf")

          with subtest("forward DNS answers exactly over UDP and TCP"):
              status(client, "dig @${serverAddress} soyo.home.arpa A", "NOERROR")
              client.succeed("test \"$(dig +short @${serverAddress} soyo.home.arpa A)\" = '${serverAddress}'")
              client.succeed("test \"$(dig +tcp +short @${serverAddress} drukarka.home.arpa A)\" = '10.0.0.11'")
              client.succeed("test \"$(dig +short @${serverAddress} cached.fixture.example.net A)\" = '192.0.2.10'")
              client.succeed("test \"$(dig +short @${serverAddress} blocked.test A)\" = '0.0.0.0'")
              status(client, "dig @${serverAddress} absent.fixture.example.net A", "NXDOMAIN")

          # The client asks Blocky on :53. This fixture-backed PTR proves only
          # that Blocky's conditional reverse-zone request reached dnsmasq on
          # :5353; the lease-backed assertion below covers dynamic PTR data.
          with subtest("reverse delegation supplies static and lease PTR records"):
              client.succeed("dig +short @${serverAddress} -x 10.0.0.11 | grep -Fx 'drukarka.home.arpa.'")

          # Unlike the fixture-backed reservation above, this PTR is created
          # from a real dnsmasq lease acquired by the client VM.
              server.succeed(f"grep -E '^[0-9]+ .+ {client_address} lease-client ' /var/lib/dnsmasq/dnsmasq.leases")
              client.succeed(f"dig +short @${serverAddress} -x {client_address} | grep -Fx 'lease-client.home.arpa.'")

          with subtest("upstream outage is bounded and recovers without Blocky restart"):
              upstream.succeed("systemctl stop dnsmasq.service")
              client.succeed("test \"$(dig +short @${serverAddress} cached.fixture.example.net A)\" = '192.0.2.10'")
              status(client, "dig @${serverAddress} outage.fixture.example.net A", "SERVFAIL")
              upstream.succeed("systemctl start dnsmasq.service")
              upstream.wait_for_unit("dnsmasq.service")
              client.wait_until_succeeds("test \"$(dig +short @${serverAddress} recovered.fixture.example.net A)\" = '192.0.2.12'")

          with subtest("dnsmasq outage does not take forward DNS down"):
              server.succeed("systemctl stop dnsmasq.service")
              client.succeed("test \"$(dig +short @${serverAddress} soyo.home.arpa A)\" = '${serverAddress}'")
              # The already-observed lease PTR remains cacheable, while a new
              # reverse lookup fails because its authoritative daemon is down.
              client.succeed(f"dig +short @${serverAddress} -x {client_address} | grep -Fx 'lease-client.home.arpa.'")
              client.succeed("! dig +short +time=1 +tries=1 @${serverAddress} -x 10.0.0.199 2>/dev/null | grep -F 'home.arpa.'")
              client.succeed("dhcpcd -n eth1 || true")
              client.succeed(f"ip -4 address show dev eth1 | grep -F '{client_address}/24'")
              server.succeed("systemctl start dnsmasq.service")
              server.wait_for_unit("dnsmasq.service")
              client.succeed("dhcpcd -n eth1")
              client.wait_until_succeeds(f"dig +short @${serverAddress} -x {client_address} | grep -Fx 'lease-client.home.arpa.'")

          with subtest("Blocky outage leaves DHCP and dnsmasq ownership intact"):
              server.succeed("systemctl stop blocky.service")
              client.fail("timeout 3s dig +time=1 +tries=1 @${serverAddress} soyo.home.arpa A")
              client.succeed("dhcpcd -n eth1")
              server.wait_until_succeeds(f"grep -E '^[0-9]+ .+ {client_address} lease-client ' /var/lib/dnsmasq/dnsmasq.leases")
              server.succeed("ss -H -lnup 'sport = :5353' | grep -F '\"dnsmasq\"'")
              server.succeed("systemctl start blocky.service")
              server.wait_for_unit("blocky.service")
              client.wait_until_succeeds("test \"$(dig +tcp +short @${serverAddress} soyo.home.arpa A)\" = '${serverAddress}'")

          with subtest("malformed UDP input cannot kill the resolver"):
              client.succeed("python3 - <<'PY'\nimport socket\ns = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)\ns.sendto(b'\\x00\\x01not-a-dns-packet', ('${serverAddress}', 53))\nPY")
              client.succeed("test \"$(dig +short @${serverAddress} soyo.home.arpa A)\" = '${serverAddress}'")

          with subtest("non-LAN interface does not expose client DNS"):
              upstream.fail("timeout 3s dig +time=1 +tries=1 @192.0.2.9 soyo.home.arpa A")

          with subtest("bounded guest pressure is only a critical-role smoke test"):
              server.succeed("systemd-run --unit=guest-pressure --property=MemoryMax=64M --property=CPUQuota=25% --property=Nice=10 python3 -c 'import time; end=time.monotonic()+4; data=bytearray(24*1024*1024); exec(\"while time.monotonic() < end:\\n sum(data)\")'")
              client.succeed("for i in $(seq 1 20); do test \"$(dig +short @${serverAddress} soyo.home.arpa A)\" = '${serverAddress}'; done")
              server.wait_until_succeeds("systemctl show guest-pressure.service -p ActiveState --value | grep -Fx inactive")

          # A service restart must reload the same on-disk lease. This proves
          # daemon restart continuity only; reboot and /persist are covered by
          # separate evaluation and live-host checks.
          with subtest("dnsmasq reloads the same durable lease after restart"):
              server.succeed("cp /var/lib/dnsmasq/dnsmasq.leases /tmp/leases.before")
              server.succeed("systemctl restart dnsmasq.service")
              server.wait_for_unit("dnsmasq.service")
              server.succeed("cmp /tmp/leases.before /var/lib/dnsmasq/dnsmasq.leases")
              client.wait_until_succeeds(f"dig +short @${serverAddress} -x {client_address} | grep -Fx 'lease-client.home.arpa.'")
        '';
      };
    };
}
