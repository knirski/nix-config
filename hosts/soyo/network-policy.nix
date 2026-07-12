# Address policy shared by DHCP generation and reservation validation. Keeping
# the dynamic pool here prevents a valid-looking reservation from silently
# overlapping a changed dnsmasq range.
{
  subnetPrefix = "10.0.0.";
  dynamicPool = {
    first = 50;
    last = 199;
    leaseTime = "12h";
  };
}
