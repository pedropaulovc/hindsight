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
unit_escape() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$' '/\\x20}
  value=${value//$'\n'/\\x0a}
  value=${value//$'\r'/\\x0d}
  value=${value//$'\t'/\\x09}
  value=${value//%/%%}
  printf '%s' "$value"
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
if [[ -z "$az_path" ]]; then
  printf '%s\n' 'Azure CLI not found; set HINDSIGHT_CP_DATAPLANE_API_KEY in the service environment file before starting.' >&2
fi


runtime_path="$(dirname -- "$npx_path"):/usr/local/bin:/usr/bin:/bin"
if [[ -n "$az_path" ]]; then
  runtime_path="$(dirname -- "$az_path"):${runtime_path}"
fi

escaped_repo_dir="$(unit_escape "$repo_dir")"
escaped_home="$(unit_escape "$HOME")"
escaped_runtime_path="$(unit_escape "$runtime_path")"
escaped_control_plane_env="$(unit_escape "$control_plane_env")"
escaped_exec_path="$(unit_escape "${repo_dir}/scripts/start-control-plane.sh")"


mkdir -p "$service_dir" "${config_dir}/hindsight"

cat >"$service_path" <<EOF
[Unit]
Description=Hindsight Control Plane
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${escaped_repo_dir}
Environment=HOME=${escaped_home}
Environment=PATH=${escaped_runtime_path}
Environment=HINDSIGHT_CP_HOSTNAME=localhost
Environment=HINDSIGHT_CP_PORT=9999
EnvironmentFile=-${escaped_control_plane_env}
ExecStart=${escaped_exec_path}

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
systemctl --user enable "$service_name"
systemctl --user restart "$service_name"

printf 'Enabled %s\n' "$service_name"
printf 'Service file: %s\n' "$service_path"
printf 'Logs: journalctl --user -u %s -f\n' "$service_name"
printf 'UI: http://localhost:9999\n'
printf 'Optional UI key file: %s\n' "$control_plane_env"
