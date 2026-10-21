# Hindsight deployment

This repository provisions the Hindsight API and its Azure dependencies.

Generation uses Azure OpenAI `gpt-6-luna`, version `2026-09-22`, in `westus3`, through the Responses API with medium reasoning effort. The `GlobalStandard` deployment has 1,000 quota units (1,000,000 TPM and 1,000 RPM). Azure model versions are pinned in `infra/main-rg.bicep`; automatic upgrades are disabled.

Reranking uses TypeSafe Jev at [https://api.typesafe.ai](https://api.typesafe.ai), with provider `typesafe`, model alias `jev-latest`, and candidate pruning explicitly disabled (`HINDSIGHT_API_RERANKER_TYPESAFE_PRUNE_CANDIDATES=false`). The alias follows TypeSafe's latest Jev release rather than pinning a model version. The API key is supplied through `HINDSIGHT_API_RERANKER_TYPESAFE_API_KEY`; there is no fallback provider.

## API image and deployment validation

The API runs the official Hindsight slim image without local source patches or a custom image build. `infra/Dockerfile` is the version pin tracked by Dependabot; Bicep reads its literal `FROM` line and deploys that image directly.

In `1.0.0-slim`, Jev can reject oversized or mixed-script requests with `max_tokens_exceeded`. Upstream [#5794](https://github.com/vectorize-io/hindsight/pull/5794) adds adaptive retries, but is not included in that release. [Issue #23](https://github.com/pedropaulovc/hindsight/issues/23) records the completed stock-image cutover and production verification.

GitHub Actions validates both Bicep entrypoints with `az bicep build --stdout` on pull requests, pushes to `main`, and manual runs, without requiring Azure credentials or application secrets for validation. Production deployment runs only on `main` after validation succeeds and uses the pinned stock image.

Workflow runs serialize per Git ref, so PR checks and branch validation cannot displace a queued production deployment.

## Deploy infrastructure

The GitHub Actions deployment uses the `prod` environment. Configure its `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` secrets for workload identity, and these application secrets:

| Secret | Purpose |
| --- | --- |
| `HINDSIGHT_API_KEY` | Authentication for Hindsight API clients |
| `TYPESAFE_API_KEY` | Authentication for the TypeSafe Jev reranker |
| `OTEL_RECEIVER_TOKEN` | Authentication for the private OTLP collector |
| `POSTGRES_ADMIN_PASSWORD` | PostgreSQL administrator password |

The workflow rejects an unset or empty `TYPESAFE_API_KEY` before deploying infrastructure. Both Bicep entrypoints require the secure `typesafeApiKey` parameter, alongside the existing secure application parameters. Never commit keys or populate parameter examples with real credentials.

For the initial subscription-scoped bootstrap, supply secrets through environment variables in a trusted shell with tracing disabled:

```bash
: "${HINDSIGHT_API_KEY:?HINDSIGHT_API_KEY must be set}"
: "${TYPESAFE_API_KEY:?TYPESAFE_API_KEY must be set}"
: "${OTEL_RECEIVER_TOKEN:?OTEL_RECEIVER_TOKEN must be set}"
: "${POSTGRES_ADMIN_PASSWORD:?POSTGRES_ADMIN_PASSWORD must be set}"
az deployment sub create \
  --location westus2 \
  --template-file infra/main.bicep \
  --parameters \
    hindsightApiKey="$HINDSIGHT_API_KEY" \
    typesafeApiKey="$TYPESAFE_API_KEY" \
    otelReceiverToken="$OTEL_RECEIVER_TOKEN" \
    postgresAdminPassword="$POSTGRES_ADMIN_PASSWORD"
```

Routine deployments use `az deployment group create --resource-group rg-hindsight-wu2 --template-file infra/main-rg.bicep` with the same four secure parameters. The `rerankEndpoint` output identifies the external TypeSafe endpoint; no Azure reranker account or model deployment is provisioned.

Deployments are incremental. Removing the former Cohere account, deployment, and reranker-specific metric alerts from Bicep does **not** delete existing Azure resources. Those resources remain unused after the Jev cutover and can be retired separately; do not switch this deployment to complete mode or delete unrelated resources.

Azure OpenAI metric alerts remain in place for HTTP 429 and other model errors. The general Hindsight application model-error alert covers TypeSafe Jev reranker errors, including exhausted HTTP 429 retries, reported in application logs. Azure OpenAI HTTP 429 and oversized embedding inputs remain excluded from this log alert; there is no TypeSafe-specific Azure metric alert.

## Open the Control Plane

The Azure deployment runs the API container only. Start the Control Plane locally and point it at the deployed API:

```bash
az login
./scripts/start-control-plane.sh
```

The script reads the API key from the `HINDSIGHT_API_TENANT_API_KEY` setting on `app-hindsight-wu2` and keeps it in the Control Plane process environment. It does not print or pass the key on the command line.

Open [http://localhost:9999](http://localhost:9999) after the server starts. The UI listens on `localhost:9999` by default.

To supply the key yourself instead of reading Azure App Service settings:

```bash
export HINDSIGHT_CP_DATAPLANE_API_KEY='your-api-key'
./scripts/start-control-plane.sh
```

When `HINDSIGHT_CP_DATAPLANE_API_URL` points to another deployment, set `HINDSIGHT_CP_DATAPLANE_API_KEY` explicitly. The launcher never sends the production key to an overridden URL.

To protect the local UI with a separate access key:

```bash
HINDSIGHT_CP_ACCESS_KEY='your-control-plane-key' ./scripts/start-control-plane.sh
```

The launcher uses `@vectorize-io/hindsight-control-plane@0.10.2`. It resolves the package before loading either key. Set `HINDSIGHT_CP_HOSTNAME` or `HINDSIGHT_CP_PORT` to override its local bind address or port.

The deployed API endpoint is [https://hindsight.vza.net](https://hindsight.vza.net). The Azure App Service origin remains `app-hindsight-wu2.azurewebsites.net`. It does not host a public Control Plane page; a hosted UI would require a separate Control Plane service.

## Run the Control Plane as a background service

To start the local Control Plane automatically with the user systemd manager:

```bash
./scripts/install-control-plane-service.sh
```

This installs and enables `hindsight-control-plane.service`, which runs
`scripts/start-control-plane.sh`, binds the UI to `localhost:9999`, restarts it
after failures, and writes output to the user journal. If the service
environment does not set `HINDSIGHT_CP_DATAPLANE_API_KEY`, the launcher reads
the backend API key from the Azure App Service settings. Check the service and
follow its logs with:

```bash
systemctl --user status hindsight-control-plane.service
journalctl --user -u hindsight-control-plane.service -f
```

On WSL, enable the systemd user manager before installing if `systemctl --user`
is unavailable. Add this to `/etc/wsl.conf`, restart WSL, and rerun the
installer:

```ini
[boot]
systemd=true
```

The service starts when the user systemd manager starts. To start it at WSL
boot before an interactive login, enable user lingering once:

```bash
loginctl enable-linger "$USER"
```

To provide the backend key without Azure CLI, or to require a separate key for
the local UI, create
`${XDG_CONFIG_HOME:-$HOME/.config}/hindsight/control-plane.env` with mode `600`:

```bash
env_file="${XDG_CONFIG_HOME:-$HOME/.config}/hindsight/control-plane.env"
install -d "$(dirname "$env_file")"
touch "$env_file"
chmod 600 "$env_file"
```

Add the required values:

```text
HINDSIGHT_CP_DATAPLANE_API_KEY=your-api-key
HINDSIGHT_CP_ACCESS_KEY=your-control-plane-key
```

Then restart the service:

```bash
systemctl --user restart hindsight-control-plane.service
```

Disable the background service with:

```bash
systemctl --user disable --now hindsight-control-plane.service
```

The service is local-only; it does not publish a hosted Control Plane endpoint.


## Custom API hostname

The base Bicep deployment creates the App Service and exposes `apiHostnameVerificationId`. The hostname binding is a separate deployment because App Service provides that verification ID only after the app exists.

When DNS is already configured, the GitHub Actions deployment runs the base deployment, hostname binding, and TLS phases. For a first bootstrap, deploy the base infrastructure, publish the DNS records, then deploy `infra/hostname-binding.bicep` and `infra/hostname-tls.bicep` in order.

| Record | Name | Value |
| --- | --- | --- |
| CNAME | `hindsight` | `app-hindsight-wu2.azurewebsites.net` |
| TXT | `asuid.hindsight` | The `apiHostnameVerificationId` deployment output |

The TXT record is the recommended App Service ownership protection. Deploy the hostname binding after both records resolve:

```bash
az deployment group create \
  --resource-group rg-hindsight-wu2 \
  --template-file infra/hostname-binding.bicep \
  --parameters \
    appName=app-hindsight-wu2 \
    apiHostname=hindsight.vza.net
```

The TLS phase creates a free App Service managed certificate and binds it with SNI:

```bash
az deployment group create \
  --resource-group rg-hindsight-wu2 \
  --template-file infra/hostname-tls.bicep \
  --parameters \
    appName=app-hindsight-wu2 \
    planName=plan-hindsight-wu2 \
    apiHostname=hindsight.vza.net
```

Wait for the managed certificate deployment to finish before using HTTPS. The certificate requires the custom hostname's CNAME to point directly to `app-hindsight-wu2.azurewebsites.net`.
