# Package: hive-grid-wallpaper — desktop background for the Ubuntu laptop
#
# Marks this machine at a glance so it is not mistaken for the other hosts.
# Purely abstract: a square lattice with a scattering of brighter cells, like
# an overhead view of a storage grid with units parked on it.
#
# Deliberately restrained. A wallpaper sits behind terminals all day, so the
# lattice stays faint and a vignette pulls the edges down; density drifts from
# the lower left to nothing in the upper right, leaving that corner calm for
# windows.
#
# Rendered at 4K and scaled by the compositor with `fill`, which covers both
# the 2560x1440 external panel and the laptop display without artefacts.
{
  lib,
  runCommand,
  resvg,
  writeText,
}:

let
  width = 3840;
  height = 2160;
  cell = 120;

  palette = {
    void = "#0B0E11";
    base = "#14181C";
    deep = "#1E6B3A";
    accent = "#4CC66E";
    lit = "#D8F3E2";
  };

  # Occupied cells as { column, row, opacity }. Hand-placed rather than
  # generated: the drift from dense lower-left to sparse upper-right is the
  # composition, and a random scatter loses it.
  units = [
    {
      c = 2;
      r = 14;
      o = 0.40;
    }
    {
      c = 3;
      r = 11;
      o = 0.26;
    }
    {
      c = 5;
      r = 15;
      o = 0.34;
    }
    {
      c = 6;
      r = 9;
      o = 0.18;
    }
    {
      c = 8;
      r = 13;
      o = 0.34;
    }
    {
      c = 9;
      r = 16;
      o = 0.22;
    }
    {
      c = 11;
      r = 10;
      o = 0.24;
    }
    {
      c = 12;
      r = 6;
      o = 0.14;
    }
    {
      c = 14;
      r = 12;
      o = 0.26;
    }
    {
      c = 16;
      r = 8;
      o = 0.16;
    }
    {
      c = 18;
      r = 15;
      o = 0.19;
    }
    {
      c = 21;
      r = 5;
      o = 0.12;
    }
    {
      c = 23;
      r = 11;
      o = 0.14;
    }
    {
      c = 27;
      r = 7;
      o = 0.10;
    }
  ];

  # Two cells in pale mint as the eye's landing points. Any more and the field
  # stops reading as a quiet background.
  highlights = [
    {
      c = 4;
      r = 13;
      o = 0.42;
    }
    {
      c = 15;
      r = 10;
      o = 0.26;
    }
  ];

  # Cells sit just inside their grid square so the lattice line stays visible
  # around them — that is what makes them read as cells rather than confetti.
  rect =
    colour: u:
    let
      inset = 14;
    in
    ''<rect x="${toString (u.c * cell + inset)}" y="${toString (u.r * cell + inset)}" ''
    + ''width="${toString (cell - 2 * inset)}" height="${toString (cell - 2 * inset)}" ''
    + ''rx="5" fill="${colour}" opacity="${toString u.o}"/>'';

  cells = lib.concatStringsSep "\n      " (
    map (rect palette.accent) units ++ map (rect palette.lit) highlights
  );

  svg = writeText "hive-grid.svg" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="${toString width}" height="${toString height}"
         viewBox="0 0 ${toString width} ${toString height}">
      <defs>
        <linearGradient id="field" x1="0" y1="1" x2="1" y2="0">
          <stop offset="0%"   stop-color="#16311F"/>
          <stop offset="38%"  stop-color="${palette.base}"/>
          <stop offset="100%" stop-color="${palette.void}"/>
        </linearGradient>

        <pattern id="hive" width="${toString cell}" height="${toString cell}" patternUnits="userSpaceOnUse">
          <path d="M ${toString cell} 0 L 0 0 0 ${toString cell}"
                fill="none" stroke="${palette.accent}" stroke-width="2" stroke-opacity="0.30"/>
        </pattern>

        <!-- Thins the lattice toward the upper right so windows sit on a clean
             field. Ends at 0.10 rather than 0, so the grid still reads there. -->
        <linearGradient id="fade" x1="0" y1="1" x2="1" y2="0">
          <stop offset="0%"   stop-color="#ffffff" stop-opacity="1"/>
          <stop offset="60%"  stop-color="#ffffff" stop-opacity="0.55"/>
          <stop offset="100%" stop-color="#ffffff" stop-opacity="0.10"/>
        </linearGradient>
        <mask id="fademask">
          <rect width="${toString width}" height="${toString height}" fill="url(#fade)"/>
        </mask>

        <radialGradient id="vignette" cx="0.30" cy="0.78" r="1.0">
          <stop offset="0%"   stop-color="${palette.void}" stop-opacity="0"/>
          <stop offset="100%" stop-color="${palette.void}" stop-opacity="0.66"/>
        </radialGradient>

        <!-- Small blur only; the cells must stay square, with the glow as a
             halo around them rather than a replacement for them. -->
        <filter id="glow" x="-40%" y="-40%" width="180%" height="180%">
          <feGaussianBlur stdDeviation="9" result="blur"/>
          <feMerge>
            <feMergeNode in="blur"/>
            <feMergeNode in="SourceGraphic"/>
            <feMergeNode in="SourceGraphic"/>
          </feMerge>
        </filter>
      </defs>

      <rect width="${toString width}" height="${toString height}" fill="url(#field)"/>
      <rect width="${toString width}" height="${toString height}" fill="url(#hive)" mask="url(#fademask)"/>

      <g mask="url(#fademask)" filter="url(#glow)">
        ${cells}
      </g>

      <rect width="${toString width}" height="${toString height}" fill="url(#vignette)"/>
    </svg>
  '';
in
runCommand "hive-grid-wallpaper.png"
  {
    nativeBuildInputs = [ resvg ];
    meta = {
      description = "Abstract storage-grid desktop background for the Ubuntu laptop";
      platforms = lib.platforms.all;
    };
  }
  ''
    resvg --width ${toString width} --height ${toString height} ${svg} "$out"
  ''
