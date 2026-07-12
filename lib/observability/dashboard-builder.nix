# Shared Grafana dashboard builder functions.
# Imported by the observability module and by per-dashboard files.
{
  lib,
  pkgs,
  ds,
  fillOpacity ? 12,
}:

let
  # Community dashboard downloader (used by fillTemplating callers)
  fetchDashboard =
    { id, hash }:
    pkgs.fetchurl {
      url = "https://grafana.com/api/dashboards/${toString id}/revisions/latest/download";
      sha256 = hash;
    };

  # Replace ${KEY} with value everywhere, then drop those template variables.
  # Handles three patterns:
  # 1. ${KEY} — datasource UIDs and JSON-embedded template refs
  # 2. "$key"  — bare PromQL template refs (quoted, in selector context)
  # 3. $key    — Grafana builtins like $__rate_interval (always → "4m")
  #    Community dashboards use this in PromQL range vectors, but
  #    Grafana resolves it to ~15s on short windows while Prometheus
  #    scrapes every 1m — rate(...[15s]) gets zero data. 4m gives
  #    enough samples without being too coarse.
  fillTemplating =
    {
      replacements,
      dashboard,
      tags ? [ ],
      extraAttrs ? { },
    }:
    let
      specification = pkgs.writeText "dashboard-render-spec.json" (
        builtins.toJSON {
          inherit extraAttrs replacements tags;
        }
      );
    in
    pkgs.runCommand "dashboard.json" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python ${./render-dashboard.py} ${dashboard} ${specification} "$out"
    '';

  mkStaticLabelTarget = t: target: {
    targets = [ target ];
    labels = {
      target_name = t.name;
      target_kind = t.kind;
      display_name = t.displayName;
      site = "lan";
    };
  };

  mkGrid = x: y: w: h: {
    inherit
      x
      y
      w
      h
      ;
  };

  mkTarget =
    refId: expr: legendFormat:
    {
      inherit expr refId;
      datasource = {
        type = "prometheus";
        uid = ds;
      };
    }
    // lib.optionalAttrs (legendFormat != null) { inherit legendFormat; };

  mkPanel = id: x: y: w: h: type: title: {
    inherit id type title;
    gridPos = mkGrid x y w h;
  };

  mkText =
    {
      id,
      x,
      y,
      w,
      h,
      title,
      content,
    }:
    mkPanel id x y w h "text" title
    // {
      options = {
        mode = "markdown";
        inherit content;
      };
      transparent = true;
    };

  mkStat =
    {
      id,
      x,
      y,
      w,
      h,
      title,
      expr,
      unit ? "none",
      description ? null,
      thresholds ? null,
      mappings ? [ ],
      decimals ? null,
    }:
    mkPanel id x y w h "stat" title
    // {
      fieldConfig.defaults = {
        inherit unit;
        color.mode = "thresholds";
      }
      // lib.optionalAttrs (description != null) { inherit description; }
      // lib.optionalAttrs (decimals != null) { inherit decimals; }
      // lib.optionalAttrs (thresholds != null) {
        thresholds = {
          mode = "absolute";
          steps = thresholds;
        };
      }
      // lib.optionalAttrs (mappings != [ ]) { inherit mappings; };
      options = {
        colorMode = "backgroundSolid";
        graphMode = "area";
        justifyMode = "center";
        orientation = "auto";
        reduceOptions = {
          calcs = [ "lastNotNull" ];
          fields = "";
          values = false;
        };
        textMode = "value";
        wideLayout = true;
      };
      targets = [ (mkTarget "A" expr null) ];
    };

  mkTimeseries =
    {
      id,
      x,
      y,
      w,
      h,
      title,
      unit,
      targets,
      description ? null,
      refIds ? [
        "A"
        "B"
        "C"
        "D"
        "E"
        "F"
        "G"
        "H"
      ],
    }:
    mkPanel id x y w h "timeseries" title
    // {
      fieldConfig.defaults = {
        inherit unit;
        color.mode = "palette-classic";
        custom = {
          axisBorderShow = false;
          drawStyle = "line";
          inherit fillOpacity;
          lineInterpolation = "smooth";
          lineWidth = 2;
          pointSize = 3;
          showPoints = "never";
          spanNulls = true;
        };
      }
      // lib.optionalAttrs (description != null) { inherit description; };
      options = {
        legend = {
          calcs = [
            "lastNotNull"
            "mean"
          ];
          displayMode = "table";
          placement = "bottom";
          showLegend = true;
        };
        tooltip = {
          mode = "multi";
          sort = "desc";
        };
      };
      targets = lib.imap0 (
        i: target: mkTarget (builtins.elemAt refIds i) target.expr target.legend
      ) targets;
    };
in
{
  inherit
    fetchDashboard
    fillTemplating
    mkStaticLabelTarget
    mkGrid
    mkTarget
    mkPanel
    mkText
    mkStat
    mkTimeseries
    ;
}
