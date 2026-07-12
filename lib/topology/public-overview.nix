{ lib }:
let
  nodes = [
    {
      x = 40;
      y = 215;
      width = 150;
      label = "Internet";
      kind = "external";
    }
    {
      x = 245;
      y = 70;
      width = 180;
      label = "Upstream DNS";
      kind = "external";
    }
    {
      x = 245;
      y = 215;
      width = 180;
      label = "Router";
      kind = "boundary";
    }
    {
      x = 500;
      y = 165;
      width = 235;
      label = "DNS + DHCP appliance";
      detail = "Critical roles";
      kind = "critical";
    }
    {
      x = 500;
      y = 350;
      width = 235;
      label = "Isolated guest services";
      kind = "guest";
    }
    {
      x = 900;
      y = 165;
      width = 190;
      label = "Workstation";
      kind = "host";
    }
    {
      x = 900;
      y = 350;
      width = 190;
      label = "Backup target";
      kind = "host";
    }
    {
      x = 40;
      y = 455;
      width = 180;
      label = "VPN administration";
      kind = "external";
    }
  ];

  palette = {
    external = {
      fill = "#eff6ff";
      stroke = "#60a5fa";
    };
    boundary = {
      fill = "#f8fafc";
      stroke = "#64748b";
    };
    critical = {
      fill = "#ecfdf5";
      stroke = "#10b981";
    };
    guest = {
      fill = "#fff7ed";
      stroke = "#f97316";
    };
    host = {
      fill = "#f5f3ff";
      stroke = "#8b5cf6";
    };
  };

  renderNode =
    node:
    let
      colors = palette.${node.kind};
      center = node.x + (node.width / 2);
    in
    ''
      <g>
        <rect x="${toString node.x}" y="${toString node.y}" width="${toString node.width}" height="86" rx="16" fill="${colors.fill}" stroke="${colors.stroke}" stroke-width="3"/>
        <text x="${toString center}" y="${toString (node.y + 40)}" text-anchor="middle" fill="#0f172a" font-family="sans-serif" font-size="18" font-weight="600">${node.label}</text>
        ${
          if node ? detail then
            ''<text x="${toString center}" y="${toString (node.y + 66)}" text-anchor="middle" fill="#475569" font-family="sans-serif" font-size="15">${node.detail}</text>''
          else
            "<!-- role-only -->"
        }
      </g>
    '';
in
''
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1160 590" width="1160" height="590" role="img" aria-labelledby="overview-title overview-description">
    <title id="overview-title">Public architecture overview</title>
    <desc id="overview-description">Role and trust flow overview</desc>
    <defs>
      <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
        <path d="M 0 0 L 10 5 L 0 10 z" fill="#64748b"/>
      </marker>
    </defs>

    <rect x="460" y="115" width="680" height="380" rx="24" fill="#ffffff" stroke="#cbd5e1" stroke-width="2" stroke-dasharray="8 8"/>
    <text x="485" y="145" fill="#475569" font-family="sans-serif" font-size="18" font-weight="600">Home LAN</text>

    <g fill="none" stroke="#64748b" stroke-width="3" marker-end="url(#arrow)">
      <path d="M 190 258 H 245"/>
      <path d="M 425 258 H 500"/>
      <path d="M 618 165 V 113 H 425"/>
      <path d="M 735 208 H 900"/>
      <path d="M 618 251 V 350"/>
      <path d="M 735 393 H 900"/>
      <path d="M 220 498 H 780 V 251 H 900"/>
    </g>

    <text x="500" y="98" fill="#475569" font-family="sans-serif" font-size="14">Encrypted DNS</text>
    <text x="760" y="382" fill="#475569" font-family="sans-serif" font-size="14">Encrypted backups</text>
    <text x="700" y="488" fill="#475569" font-family="sans-serif" font-size="14">Remote access</text>

    ${lib.concatMapStrings renderNode nodes}
  </svg>
''
