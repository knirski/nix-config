{
  lib,
  config,
  pkgs,
  ...
}:
{
  systemd.services.grafana-alert-setup = {
    description = "Provision Grafana alerting rules and ntfy contact point";
    after = [ "grafana.service" ];
    wants = [ "grafana.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      MemoryMax = "64M";
      CPUQuota = "10%";
      Nice = 10;
      ExecStart =
        let
          script = pkgs.writeShellApplication {
            name = "grafana-alert-setup";
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
              curl() { command curl -sf -u "$AUTH" "$@"; }

              wait_ready() {
                for _ in $(seq 1 30); do
                  curl "$BASE/api/health" >/dev/null 2>&1 && return 0
                  sleep 2
                done
                exit 1
              }

              ensure_folder() {
                command curl -sS -u "$AUTH" -o /dev/null -w '%{http_code}' \
                  -X POST -H 'Content-Type: application/json' \
                  -d '{"uid":"soyo","title":"Soyo"}' \
                  "$BASE/api/folders" | grep -qE '^200|^409|^412'
                curl -sS -o /dev/null -X PUT \
                  -H 'Content-Type: application/json' \
                  -d '{"uid":"soyo","title":"Soyo","overwrite":true}' \
                  "$BASE/api/folders/soyo" || :
              }

              cleanup_legacy_folder() {
                local legacy_uids uid status
                legacy_uids=$(command curl -sS -u "$AUTH" "$BASE/api/folders" \
                  | ${pkgs.jq}/bin/jq -r '.[] | select(.title == "soyo" and .uid != "soyo") | .uid')

                for uid in $legacy_uids; do
                  status=$(command curl -sS -u "$AUTH" -o /dev/null -w '%{http_code}' \
                    -X DELETE "$BASE/api/folders/$uid")
                  [ "$status" = 200 ] || [ "$status" = 204 ] || [ "$status" = 404 ]
                done
              }

              provision_contact_point() {
                local topic token existing payload
                topic=$(<"$CREDENTIALS_DIRECTORY"/ntfy_topic)
                token=$(<"$CREDENTIALS_DIRECTORY"/ntfy_token)
                existing=$(command curl -sS -u "$AUTH" "$BASE/api/v1/provisioning/contact-points")
                if printf '%s' "$existing" | ${pkgs.jq}/bin/jq -e 'any(.. | objects; .name? == "ntfy")' >/dev/null; then
                  return 0
                fi
                payload=$(${pkgs.jq}/bin/jq -nc --arg url "$topic" --arg token "$token" '{name: "ntfy", type: "webhook", settings: {url: ($url + "?template=yes&title=%7B%7B.title%7D%7D&message=%7B%7B.message%7D%7D&priority=5&tags=warning,soyo"), httpMethod: "POST", authorization: {type: "Bearer", credentials: $token}}}')
                printf '%s' "$payload" | curl -X POST -H 'Content-Type: application/json' -d @- "$BASE/api/v1/provisioning/contact-points"
              }

              provision_policy() {
                ${pkgs.jq}/bin/jq -nc \
                  '{receiver: "ntfy", group_by: ["severity", "team"],
                    group_wait: "30s", group_interval: "5m",
                    repeat_interval: "4h", routes: []}' \
                  | curl -X PUT -H 'Content-Type: application/json' \
                    -d @- "$BASE/api/v1/provisioning/policies"
              }

              delete_rule() {
                local uid="$1" status
                status=$(command curl -sS -u "$AUTH" -o /dev/null -w '%{http_code}'                   -X DELETE "$BASE/api/v1/provisioning/alert-rules/$uid")
                [ "$status" = 200 ] || [ "$status" = 202 ] || [ "$status" = 204 ] || [ "$status" = 404 ]
              }

              wait_rule_gone() {
                local uid="$1"
                for _ in $(seq 1 20); do
                  if ! command curl -sS -u "$AUTH" "$BASE/api/v1/provisioning/alert-rules"                     | ${pkgs.jq}/bin/jq -e --arg uid "$uid" '.[] | select(.uid == $uid)' >/dev/null; then
                    return 0
                  fi
                  sleep 1
                done
                return 1
              }

              post_rule() {
                local uid="$1"
                delete_rule "$uid"
                wait_rule_gone "$uid"
                ${pkgs.jq}/bin/jq -nc \
                  --arg uid "$uid" --arg title "$2" \
                  --arg expr "$3" --arg for "$4" \
                  --arg noData "$5" --arg summary "$6" \
                  '{uid: $uid, title: $title,
                    folderUID: "soyo", ruleGroup: "soyo", orgID: 1,
                    condition: "A", noDataState: $noData,
                    execErrState: "KeepLast", for: $for,
                    data: [{
                      refId: "A",
                      relativeTimeRange: {from: 600, to: 0},
                      datasourceUid: "soyo-prometheus",
                      model: {type: "prometheus", expr: $expr}
                    }],
                    annotations: {summary: $summary},
                    labels: {severity: "critical", team: "soyo"},
                    isPaused: false}' \
                  | curl -X POST -H 'Content-Type: application/json' \
                    -d @- "$BASE/api/v1/provisioning/alert-rules"
              }

              provision_rules() {
                post_rule soyo_blocky_down \
                  "🧱 Blocky DNS down" \
                  'up{job="blocky"} == 0' \
                  5m KeepLast "🧱 Blocky DNS is unreachable"

                post_rule soyo_dnsmasq_down \
                  "📡 dnsmasq down" \
                  'up{job="dnsmasq"} == 0' \
                  5m KeepLast "📡 dnsmasq is unreachable — DHCP and reverse DNS are down"

                post_rule soyo_backup_failed \
                  "🛟 Backup failed" \
                  'restic_backup_ran == 1 and restic_backup_success == 0' \
                  30m KeepLast "🛟 Restic backup to Synology failed — check journalctl"

                post_rule soyo_disk_space_low \
                  "💽 Btrfs space low" \
                  'soyo_btrfs_usage_percent > soyo_btrfs_usage_threshold_percent' \
                  5m KeepLast "💽 Btrfs filesystem usage is above the configured threshold"
              }

              wait_ready
              ensure_folder
              cleanup_legacy_folder
              provision_contact_point
              provision_policy
              provision_rules
            '';
          };
        in
        "${script}/bin/grafana-alert-setup";
      LoadCredential = [
        "ntfy_topic:${config.age.secrets.ntfy-topic.path}"
        "ntfy_token:${config.age.secrets.ntfy-token.path}"
        "admin_password:${config.age.secrets.grafana-admin-password.path}"
      ];
    };
  };
}
