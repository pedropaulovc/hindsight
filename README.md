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

The deployed API endpoint is [https://app-hindsight-wu2.azurewebsites.net](https://app-hindsight-wu2.azurewebsites.net). It does not host a public Control Plane page; a hosted UI would require a separate Control Plane service.
