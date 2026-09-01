#!/usr/bin/env bash
set -euo pipefail

readonly default_api_url="https://app-hindsight-wu2.azurewebsites.net"
readonly api_url="${HINDSIGHT_CP_DATAPLANE_API_URL:-$default_api_url}"

xtrace_was_enabled=0
case "$-" in
  *x*)
    xtrace_was_enabled=1
    set +x
    ;;
esac

api_key_from_env="${HINDSIGHT_CP_DATAPLANE_API_KEY-}"
ui_access_key_from_env="${HINDSIGHT_CP_ACCESS_KEY-}"

if [[ "$api_url" != "$default_api_url" && -z "$api_key_from_env" ]]; then
  if (( xtrace_was_enabled )); then
    set -x
  fi
  printf '%s\n' 'Set HINDSIGHT_CP_DATAPLANE_API_KEY when overriding HINDSIGHT_CP_DATAPLANE_API_URL.' >&2
  exit 1
fi

unset HINDSIGHT_CP_DATAPLANE_API_KEY HINDSIGHT_CP_ACCESS_KEY

set +e
npx --yes --ignore-scripts @vectorize-io/hindsight-control-plane@0.9.2 --help >/dev/null
package_status=$?
set -e

if (( package_status != 0 )); then
  unset api_key_from_env ui_access_key_from_env
  if (( xtrace_was_enabled )); then
    set -x
  fi
  printf '%s\n' 'Unable to resolve the Hindsight Control Plane package.' >&2
  exit "$package_status"
fi

if [[ -n "$api_key_from_env" ]]; then
  HINDSIGHT_CP_DATAPLANE_API_KEY="$api_key_from_env"
else
  if ! command -v az >/dev/null 2>&1; then
    unset api_key_from_env ui_access_key_from_env
    if (( xtrace_was_enabled )); then
      set -x
    fi
    printf '%s\n' 'Set HINDSIGHT_CP_DATAPLANE_API_KEY or install and authenticate with Azure CLI.' >&2
    exit 1
  fi

  set +e
  HINDSIGHT_CP_DATAPLANE_API_KEY="$(
    az webapp config appsettings list \
      --resource-group rg-hindsight-wu2 \
      --name app-hindsight-wu2 \
      --query "[?name=='HINDSIGHT_API_TENANT_API_KEY'].value | [0]" \
      --output tsv
  )"
  lookup_status=$?
  set -e

  if (( lookup_status != 0 )); then
    unset api_key_from_env ui_access_key_from_env HINDSIGHT_CP_DATAPLANE_API_KEY
    if (( xtrace_was_enabled )); then
      set -x
    fi
    printf '%s\n' 'Unable to read HINDSIGHT_API_TENANT_API_KEY from Azure App Service settings.' >&2
    exit "$lookup_status"
  fi
fi

unset api_key_from_env

if [[ -z "${HINDSIGHT_CP_DATAPLANE_API_KEY:-}" ]]; then
  unset ui_access_key_from_env HINDSIGHT_CP_DATAPLANE_API_KEY
  if (( xtrace_was_enabled )); then
    set -x
  fi
  printf '%s\n' 'HINDSIGHT_API_TENANT_API_KEY was not found in the Azure App Service settings.' >&2
  exit 1
fi

if [[ -n "$ui_access_key_from_env" ]]; then
  HINDSIGHT_CP_ACCESS_KEY="$ui_access_key_from_env"
fi
unset ui_access_key_from_env

export HINDSIGHT_CP_DATAPLANE_API_URL="$api_url"
export HINDSIGHT_CP_DATAPLANE_API_KEY

if (( xtrace_was_enabled )); then
  set -x
fi

exec npx --no-install @vectorize-io/hindsight-control-plane@0.9.2 \
  --api-url "$api_url" \
  --hostname "${HINDSIGHT_CP_HOSTNAME:-localhost}" \
  --port "${HINDSIGHT_CP_PORT:-9999}"
