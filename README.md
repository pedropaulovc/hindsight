# Hindsight deployment

This repository provisions the Hindsight API and its Azure dependencies.

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

The launcher uses `@vectorize-io/hindsight-control-plane@0.9.2`. It resolves the package before loading either key. Set `HINDSIGHT_CP_HOSTNAME` or `HINDSIGHT_CP_PORT` to override its local bind address or port.

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
