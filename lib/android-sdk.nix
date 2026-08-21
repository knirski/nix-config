# Shared Android SDK composition for Linux development hosts.
#
# Keep the emulator image deliberately narrow: the workstation is x86_64, so
# ARM images add bulk without serving the local development workflow.
{ pkgs }:
pkgs.androidenv.composeAndroidPackages {
  includeEmulator = true;
  includeSystemImages = true;
  includeNDK = false;
  # The repository currently names the newest platform's image archive 37.0,
  # while the generic "latest" platform selector resolves to 37 and produces
  # no matching system image.
  platformVersions = [ "37.0" ];
  systemImageTypes = [ "google_apis" ];
  abiVersions = [ "x86_64" ];
}
