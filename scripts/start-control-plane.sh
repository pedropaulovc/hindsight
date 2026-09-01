#!/usr/bin/env bash
set -euo pipefail

readonly api_url="${HINDSIGHT_CP_DATAPLANE_API_URL:-https://app-hindsight-wu2.azurewebsites.net}"

if [[ -z "${HINDSIGHT_CP_DATAPLANE_API_KEY:-}" ]]; then
  if ! command -v az >/dev/null 2>&1; then
    printf '%s\n' 'Set HINDSIGHT_CP_DATAPLANE_API_KEY or install and authenticate with Azure CLI.' >&2
    exit 1
  fi

  HINDSIGHT_CP_DATAPLANE_API_KEY="$(
    az webapp config appsettings list \
      --resource-group rg-hindsight-wu2 \
      --name app-hindsight-wu2 \
      --query "[?name=='HINDSIGHT_API_TENANT_API_KEY'].value | [0]" \
      --output tsv
  )"
fi

if [[ -z "${HINDSIGHT_CP_DATAPLANE_API_KEY:-}" ]]; then
  printf '%s\n' 'HINDSIGHT_API_TENANT_API_KEY was not found in the Azure App Service settings.' >&2
  exit 1
fi

export HINDSIGHT_CP_DATAPLANE_API_URL="$api_url"
export HINDSIGHT_CP_DATAPLANE_API_KEY

exec npx --yes @vectorize-io/hindsight-control-plane@0.9.2 \
  --api-url "$api_url" \
  --hostname "${HINDSIGHT_CP_HOSTNAME:-localhost}" \
  --port "${HINDSIGHT_CP_PORT:-9999}"
