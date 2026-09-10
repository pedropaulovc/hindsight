#!/usr/bin/env bash
set -euo pipefail

readonly service_name='hindsight-control-plane.service'
readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd -- "${script_dir}/.." && pwd)"
readonly config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}"
readonly service_dir="${config_dir}/systemd/user"
readonly service_path="${service_dir}/${service_name}"
readonly control_plane_env="${config_dir}/hindsight/control-plane.env"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

command -v systemctl >/dev/null 2>&1 || fail 'systemctl is required to install the user service.'

npx_path="$(command -v npx || true)"
if [[ -z "$npx_path" ]]; then
  nvm_dir="${NVM_DIR:-${HOME}/.nvm}"
  if [[ -s "${nvm_dir}/nvm.sh" ]]; then
    # shellcheck disable=SC1090
    . "${nvm_dir}/nvm.sh"
    npx_path="$(command -v npx || true)"
  fi
fi
[[ -n "$npx_path" ]] || fail 'npx is required. Install Node.js or configure nvm before installing the service.'

az_path="$(command -v az || true)"
[[ -n "$az_path" ]] || fail 'Azure CLI is required because the launcher reads the API key from App Service settings.'

mkdir -p "$service_dir" "${config_dir}/hindsight"

cat >"$service_path" <<EOF
[Unit]
Description=Hindsight Control Plane
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${repo_dir}
Environment=HOME=${HOME}
Environment=PATH=$(dirname -- "$npx_path"):$(dirname -- "$az_path"):/usr/local/bin:/usr/bin:/bin
Environment=HINDSIGHT_CP_HOSTNAME=localhost
Environment=HINDSIGHT_CP_PORT=9999
EnvironmentFile=-${control_plane_env}
ExecStart=${repo_dir}/scripts/start-control-plane.sh
Restart=on-failure
RestartSec=5s
TimeoutStartSec=10min
TimeoutStopSec=15s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=hindsight-control-plane

[Install]
WantedBy=default.target
EOF

chmod 0644 "$service_path"
systemctl --user daemon-reload
systemctl --user enable --now "$service_name"

printf 'Enabled %s\n' "$service_name"
printf 'Service file: %s\n' "$service_path"
printf 'Logs: journalctl --user -u %s -f\n' "$service_name"
printf 'UI: http://localhost:9999\n'
printf 'Optional UI key file: %s\n' "$control_plane_env"
