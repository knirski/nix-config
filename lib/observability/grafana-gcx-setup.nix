# Systemd oneshot service: create a "gcx" Grafana service account with Admin
# role and a long-lived API token, then write the token to
# /var/lib/grafana/gcx-token so operators can retrieve it over SSH and
# configure gcx on their workstations (e.g. `gcx login soyo --server
# http://soyo:3000 --token $(ssh soyo sudo cat /var/lib/grafana/gcx-token)`).
#
# Idempotent: if the service account and token already exist, skips creation.
#
# Depends on grafana.service and the admin password secret (via LoadCredential).
{ config, pkgs, ... }:

let
  hardening = import ../systemd-hardening.nix;
in
{
  systemd.services.grafana-gcx-setup = {
    description = "Provision Grafana gcx service account and API token";
    after = [ "grafana.service" ];
    wants = [ "grafana.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = hardening.networkClient // {
      Type = "oneshot";
      RemainAfterExit = true;
      MemoryMax = "64M";
      CPUQuota = "10%";
      Nice = 10;
      TimeoutStartSec = "2m";
      Restart = "no";
      ExecStart =
        let
          script = pkgs.writeShellApplication {
            name = "grafana-gcx-setup";
            runtimeInputs = [
              pkgs.curl
              pkgs.jq
            ];
            excludeShellChecks = [ "SC2086" ];
            text = ''
              set -eu
              : "''${CREDENTIALS_DIRECTORY:=/dev/null}"
              PASS=$(<"$CREDENTIALS_DIRECTORY"/admin_password)
              AUTH="admin:$PASS"
              BASE=http://127.0.0.1:3000
              TOKEN_FILE=/var/lib/grafana/gcx-token
              curl() { command curl -sf -u "$AUTH" "$@"; }

              wait_ready() {
                for _ in $(seq 1 30); do
                  curl "$BASE/api/health" >/dev/null 2>&1 && return 0
                  sleep 2
                done
                exit 1
              }

              find_sa_id() {
                # Search for a service account named "gcx".
                # Returns the numeric id (or empty string if not found).
                curl -sS "$BASE/api/serviceaccounts/search?perpage=100&page=1&query=gcx" \
                  | ${pkgs.jq}/bin/jq -r '.serviceAccounts[] | select(.name == "gcx") | .id // empty'
              }

              create_sa() {
                curl -sS -X POST -H 'Content-Type: application/json' \
                  -d '{"name":"gcx","role":"Admin","isDisabled":false}' \
                  "$BASE/api/serviceaccounts" \
                  | ${pkgs.jq}/bin/jq -r '.id'
              }

              create_token() {
                local sa_id="$1"
                curl -sS -X POST -H 'Content-Type: application/json' \
                  -d '{"name":"gcx-token"}' \
                  "$BASE/api/serviceaccounts/$sa_id/tokens" \
                  | ${pkgs.jq}/bin/jq -r '.key'
              }

              # --- Main ---
              wait_ready

              # Exit early if token file already exists (idempotent).
              if [ -f "$TOKEN_FILE" ] && [ -s "$TOKEN_FILE" ]; then
                echo "gcx token already provisioned at $TOKEN_FILE, skipping"
                exit 0
              fi

              sa_id=$(find_sa_id)
              if [ -z "$sa_id" ]; then
                echo "creating gcx service account ..."
                sa_id=$(create_sa)
              else
                echo "gcx service account already exists (id=$sa_id)"
              fi

              echo "creating gcx API token ..."
              token=$(create_token "$sa_id")

              # Write token atomically so a concurrent read never sees a
              # partial write.  grafana:grafana matches the owner of
              # /var/lib/grafana so the file stays inside the persisted tree.
              tmp=$(mktemp /var/lib/grafana/.gcx-token.XXXXXX)
              printf '%s\n' "$token" > "$tmp"
              chown grafana:grafana "$tmp"
              chmod 0440 "$tmp"
              mv "$tmp" "$TOKEN_FILE"

              echo "gcx token written to $TOKEN_FILE"
            '';
          };
        in
        "${script}/bin/grafana-gcx-setup";
      LoadCredential = [
        "admin_password:${config.age.secrets.grafana-admin-password.path}"
      ];
    };
  };
}
