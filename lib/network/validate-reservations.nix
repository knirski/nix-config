# Validate the LAN inventory before it becomes dnsmasq or Blocky configuration.
#
# A name may occur more than once: that is how a multihomed host gets multiple
# A records. MAC and IP addresses identify individual interfaces and therefore
# must be unique across the inventory.
{
  reservations,
  subnetPrefix,
  dynamicPool,
}:

let
  indexedReservations = builtins.genList (index: {
    inherit index;
    value = builtins.elemAt reservations index;
  }) (builtins.length reservations);

  requiredFields = [
    "name"
    "mac"
    "ip"
  ];
  shapeErrors = builtins.concatLists (
    map (
      entry:
      if !builtins.isAttrs entry.value then
        [ "entry ${toString entry.index} must be an attribute set" ]
      else
        builtins.concatLists (
          map (
            field:
            if !builtins.hasAttr field entry.value then
              [ "entry ${toString entry.index} is missing required field `${field}`" ]
            else if !builtins.isString entry.value.${field} then
              [ "entry ${toString entry.index} field `${field}` must be a string" ]
            else
              [ ]
          ) requiredFields
        )
    ) indexedReservations
  );
  wellShaped = builtins.filter (
    reservation:
    builtins.isAttrs reservation
    && builtins.all (
      field: builtins.hasAttr field reservation && builtins.isString reservation.${field}
    ) requiredFields
  ) reservations;

  validDnsLabel =
    name:
    builtins.isString name
    && builtins.stringLength name <= 63
    && builtins.match "[a-z0-9]([a-z0-9-]*[a-z0-9])?" name != null;

  validMac =
    mac: builtins.isString mac && builtins.match "[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}" mac != null;

  parseIPv4 =
    ip:
    let
      match =
        if builtins.isString ip then
          builtins.match "([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})" ip
        else
          null;
      parsed =
        if match == null then [ ] else map (octet: builtins.tryEval (builtins.fromJSON octet)) match;
    in
    if match == null || !builtins.all (octet: octet.success) parsed then
      null
    else
      map (octet: octet.value) parsed;

  validIPv4 =
    ip:
    let
      octets = parseIPv4 ip;
    in
    octets != null && builtins.all (octet: octet >= 0 && octet <= 255) octets;

  duplicateValues =
    values:
    builtins.filter
      (value: builtins.length (builtins.filter (candidate: candidate == value) values) > 1)
      (
        builtins.attrNames (
          builtins.listToAttrs (
            map (value: {
              name = value;
              value = true;
            }) values
          )
        )
      );

  lowercaseHex =
    value: builtins.replaceStrings [ "A" "B" "C" "D" "E" "F" ] [ "a" "b" "c" "d" "e" "f" ] value;
  macs = map (reservation: lowercaseHex reservation.mac) wellShaped;
  ips = map (reservation: reservation.ip) wellShaped;

  malformedNames = map (reservation: reservation.name) (
    builtins.filter (reservation: !validDnsLabel reservation.name) wellShaped
  );
  malformedMacs = map (reservation: reservation.mac) (
    builtins.filter (reservation: !validMac reservation.mac) wellShaped
  );
  malformedIps = map (reservation: reservation.ip) (
    builtins.filter (reservation: !validIPv4 reservation.ip) wellShaped
  );
  outsideSubnet = map (reservation: reservation.ip) (
    builtins.filter (
      reservation:
      validIPv4 reservation.ip
      && builtins.substring 0 (builtins.stringLength subnetPrefix) reservation.ip != subnetPrefix
    ) wellShaped
  );
  overlapsDynamicPool = map (reservation: reservation.ip) (
    builtins.filter (
      reservation:
      let
        octets = parseIPv4 reservation.ip;
        host = if octets == null then null else builtins.elemAt octets 3;
      in
      host != null && host >= dynamicPool.first && host <= dynamicPool.last
    ) wellShaped
  );
  unusableHostAddresses = map (reservation: reservation.ip) (
    builtins.filter (
      reservation:
      let
        octets = parseIPv4 reservation.ip;
        host = if octets == null then null else builtins.elemAt octets 3;
      in
      host == 0 || host == 255
    ) wellShaped
  );

  errors =
    shapeErrors
    ++ (map (value: "duplicate MAC address (case-insensitive): ${value}") (duplicateValues macs))
    ++ (map (value: "duplicate IP address: ${value}") (duplicateValues ips))
    ++ (map (value: "invalid DNS label: ${toString value}") malformedNames)
    ++ (map (value: "invalid MAC address: ${toString value}") malformedMacs)
    ++ (map (value: "invalid IPv4 address: ${toString value}") malformedIps)
    ++ (map (value: "reservation is outside subnet ${subnetPrefix}0/24: ${value}") outsideSubnet)
    ++ (map (value: "reservation uses a network or broadcast address: ${value}") unusableHostAddresses)
    ++ (map (
      value:
      "reservation overlaps dynamic DHCP pool ${subnetPrefix}${toString dynamicPool.first}-${toString dynamicPool.last}: ${value}"
    ) overlapsDynamicPool);
in
if errors == [ ] then
  reservations
else
  throw "Invalid Soyo reservation inventory:\n- ${builtins.concatStringsSep "\n- " errors}"
