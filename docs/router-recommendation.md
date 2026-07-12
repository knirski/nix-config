# Router role recommendation

Would you recommend using Soyo as a router (with a second Ethernet interface,
such as a USB-C RTL8153 adapter), and how should it be connected? The current
layout uses an Orange Funbox 6 connected to WAN and a Netgear Orbi RBR50 with
two satellites as a second router and mesh Wi-Fi provider.

I’ll assess the failure domains and verify the relevant Orbi AP-mode and Funbox capabilities from primary documentation. The key question is whether making Soyo the gateway improves control enough to justify putting routing behind a USB NIC and expanding the appliance’s critical role.

Searching the web

Searched the web for site:kb.netgear.com RBR50 AP mode Internet port router mode access point ...

I would not make Soyo the router by default. It conflicts with the repository’s strongest invariant—DNS and DHCP are its only critical roles—and makes every Soyo reboot, bad deployment, USB-NIC reset, or firewall mistake an internet outage.

A better simplification is:

```text
Internet
   │
Funbox 6                    gateway/NAT: 192.168.1.1
   │ LAN
   ├── Soyo                 DNS + DHCP: 192.168.1.9
   └── Orbi RBR50           AP mode, mesh Wi-Fi
          ├── satellite
          └── satellite
```

This requires migrating the LAN from `10.0.0.0/24` to `192.168.1.0/24`, disabling DHCP on the Funbox, and changing Orbi to AP mode. Netgear officially supports connecting the existing router’s LAN port to the RBR50 Internet port and then selecting AP mode; the satellites continue to form the mesh. [Netgear AP-mode instructions](https://kb.netgear.com/31218/How-do-I-configure-my-Orbi-router-to-act-as-an-access-point), [RBR50 manual](https://www.downloads.netgear.com/files/GDC/RBK50/Orbi_UM_EN.pdf).

Advantages:

- only one router/NAT layer;
- no USB NIC in the critical path;
- Soyo retains its deliberately narrow DNS/DHCP role;
- Orbi provides Wi-Fi only;
- Funbox retains Orange-specific WAN, telephone and firmware integration;
- failure of Soyo affects DNS/new leases, but does not remove the physical gateway.

First verify that your Funbox UI permits disabling its DHCP server. If it cannot, this arrangement becomes awkward because Soyo and Funbox must not both serve DHCP.

## If you deliberately want Soyo as router

It is technically reasonable if you want a declarative firewall, NAT, routing policy, VPN routing, or future VLANs badly enough to accept the larger failure domain.

Connect it like this:

```text
Internet
   │
Funbox 6
LAN: 192.168.1.1/24
   │
   │ Ethernet
   ▼
Soyo USB RTL8153                 WAN
192.168.1.2/24
   │
   │ routing + firewall + NAT
   │
Soyo onboard enp1s0             LAN
10.0.0.1/24
   │
   ▼
Orbi RBR50 Internet port
AP mode
   ├── RBS50 satellite
   └── RBS50 satellite
```

Use the NICs in that order:

- **Onboard Motorcomm NIC → trusted LAN.** It is the more dependable, in-tree interface and should carry DNS, DHCP and local management.
- **USB RTL8153 → untrusted Funbox/WAN side.** If it disconnects, internet access fails, but local DNS, DHCP and LAN communication can remain operational.

Do not attach both Soyo interfaces to the same LAN or switch. The Funbox-side network and household LAN must remain separate routed networks.

Netgear’s official AP-mode topology uses the RBR50’s Internet/WAN port for its upstream connection. [Netgear explicitly recommends AP mode when another router is present](https://kb.netgear.com/fr/31117/Puis-je-utiliser-le-routeur-Orbi-avec-une-passerelle-ou-un-modem-existants).

### Funbox configuration

Give Soyo’s USB interface a stable Funbox-side address, for example:

```text
Funbox:       192.168.1.1
Soyo WAN:     192.168.1.2
```

Prefer a DHCP reservation on the Funbox rather than an address that might overlap its pool.

If supported, set the Funbox DMZ host to `192.168.1.2`. That avoids configuring every inbound port twice, but it does not eliminate double NAT:

```text
Internet → Funbox NAT → Soyo NAT → LAN
```

Do not expose Soyo management services on the WAN interface merely because it is the DMZ target. Its firewall should accept essentially nothing unsolicited from the Funbox side.

I would not attempt to replace or bridge the Funbox until you have confirmed the Orange requirements for your exact connection, particularly PPPoE, VLANs, IPv6 prefix delegation, telephone and IPTV. Those services can make direct replacement substantially more complicated.

### LAN changes

Soyo would take over the address currently used by Orbi:

```text
Soyo LAN/gateway/DNS: 10.0.0.1
DHCP pool:            10.0.0.50–199
Search domain:        home.arpa
```

The RBR50 and satellites need new non-conflicting management addresses. For example:

```text
RBR50:        10.0.0.2
Satellite 1:  10.0.0.3
Satellite 2:  10.0.0.4
Soyo:         10.0.0.1
```

That requires updating the current reservations, because `.2` and `.3` are already assigned to the satellites and Soyo currently uses `.9`.

### Before relying on RTL8153

Test the adapter for several days before putting it in the routing path:

- sustained throughput in both directions;
- repeated unplug/replug recovery;
- cold boot and reboot detection;
- suspend/autosuspend disabled;
- stable interface matching by MAC or hardware path;
- carrier-loss monitoring and alerts;
- no resets under load in `journalctl -k`;
- spare adapter available.

Use a good USB 3.x adapter and a port that does not share an unreliable dock or hub. The RTL8153 is generally fast enough for gigabit routing, but USB remains mechanically and operationally less dependable than an onboard NIC.

## Important IPv6 decision

Do not migrate routing without deciding IPv6 explicitly.

If Funbox advertises IPv6 directly across an unintended path, clients could bypass Soyo’s routing, firewall or DNS policy. Either:

- intentionally implement DHCPv6 prefix delegation and router advertisements on Soyo; or
- deliberately disable IPv6 forwarding/advertisement on the new LAN until it is designed and tested.

Avoid an accidental half-working IPv6 setup.

## My recommendation

In order of preference:

1. **Funbox remains router, Orbi becomes AP, Soyo remains DNS/DHCP.** Cleanest and most consistent with the project.
2. **Keep the present topology** if readdressing the LAN is not worth the disruption.
3. **Make Soyo the router only as a deliberate new milestone**, with routing treated as a third critical role and the canonical design changed first.

If you choose option 3, use the RTL8153 for WAN and the onboard NIC for LAN. I would implement it as a new router aspect with nftables, explicit interface zones, forwarding/NAT tests, DHCP/DNS failure-isolation tests, and a documented Funbox-bypass rollback—not as a few networking options added to the existing server module.
