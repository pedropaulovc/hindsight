targetScope = 'resourceGroup'

@description('Azure region for the App Service, database, and monitoring resources.')
param location string = 'westus2'

@description('Azure region for Azure OpenAI. GPT-5.6-luna is not listed for westus2, so the default is westus3.')
param aiLocation string = 'westus3'

@description('PostgreSQL administrator login.')
param postgresAdminLogin string = 'hindsightadmin'

@secure()
@description('PostgreSQL administrator password.')
param postgresAdminPassword string

@secure()
@description('API key required by Hindsight clients.')
param hindsightApiKey string

@secure()
@description('Bearer token accepted by the private OTLP collector endpoint.')
param otelReceiverToken string

@description('PostgreSQL Flexible Server name.')
param postgresServerName string = 'pg-hindsight-wu2'

@description('Database name used by Hindsight.')
param postgresDatabaseName string = 'hindsight'

@description('Azure OpenAI account name.')
param llmAccountName string = 'cog-hindsight-wu2'

@description('Azure AI Services account name used for reranking.')
param rerankAccountName string = 'rerank-hindsight-wu2'

@description('Azure OpenAI deployment name for GPT-5.6-luna.')
param llmDeploymentName string = 'gpt-5-6-luna'

@description('Azure OpenAI deployment name for text-embedding-3-small.')
param embeddingDeploymentName string = 'embedding-3-small'

@description('Azure AI Services deployment name for Cohere reranking.')
param rerankDeploymentName string = 'cohere-rerank-v4-0-pro'

@description('App Service plan name.')
param planName string = 'plan-hindsight-wu2'

@description('Hindsight API App Service name.')
param appName string = 'app-hindsight-wu2'

@description('OTLP collector App Service name.')
param collectorAppName string = 'otel-hindsight-wu2'

@description('Log Analytics workspace name.')
param logAnalyticsName string = 'law-hindsight-wu2'

@description('Azure Monitor workspace name.')
param monitorWorkspaceName string = 'amw-hindsight-wu2'

@description('Application Insights resource name.')
param applicationInsightsName string = 'ai-hindsight-wu2'

@description('Data Collection Endpoint name.')
param dataCollectionEndpointName string = 'dce-hindsight-wu2'

@description('Data Collection Rule name.')
param dataCollectionRuleName string = 'dcr-hindsight-wu2'

@description('Existing deployment identity created by infra/bootstrap.bicep.')
param deploymentIdentityName string = 'id-hindsight-deploy-wu2'

@description('Existing OTLP collector identity created by infra/bootstrap.bicep.')
param otelIdentityName string = 'id-hindsight-otel-wu2'

var hindsightImage = 'ghcr.io/vectorize-io/hindsight-api:0.9.2-slim'
var collectorImage = 'otel/opentelemetry-collector-contrib:0.132.0'
var llmModelName = 'gpt-5.6-luna'
var llmModelVersion = '2026-07-09'
var embeddingModelName = 'text-embedding-3-small'
var embeddingModelVersion = '1'
var rerankModelName = 'Cohere-rerank-v4.0-pro'
var rerankModelVersion = '1'
var postgresConnectionString = 'postgresql://${postgresAdminLogin}:${uriComponent(postgresAdminPassword)}@${postgresServerName}.postgres.database.azure.com:5432/${postgresDatabaseName}?sslmode=require'
var llmBaseUrl = 'https://${llmAccountName}.openai.azure.com/openai/v1'
var embeddingBaseUrl = 'https://${llmAccountName}.openai.azure.com/openai/deployments/${embeddingDeploymentName}'
var rerankBaseUrl = 'https://${rerankAccountName}.services.ai.azure.com/providers/cohere/v2/rerank'
var collectorBaseUrl = 'https://${collectorAppName}.azurewebsites.net'
var tracesStreamName = 'Microsoft-OTel-Traces-Spans'

resource deploymentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: deploymentIdentityName
}

resource otelIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: otelIdentityName
}

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: postgresServerName
  location: location
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: postgresAdminLogin
    administratorLoginPassword: postgresAdminPassword
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
    availabilityZone: '1'
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    network: {
      publicNetworkAccess: 'Enabled'
    }
    storage: {
      autoGrow: 'Disabled'
      storageSizeGB: 32
    }
    version: '16'
  }
  tags: {
    application: 'hindsight'
    managedBy: 'bicep'
  }
}

resource postgresDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  name: postgresDatabaseName
  parent: postgres
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

resource postgresVectorConfiguration 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  name: 'azure.extensions'
  parent: postgres
  properties: {
    value: 'vector'
    source: 'user-override'
  }
}

resource postgresFirewall 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  name: 'AllowAzureServices'
  parent: postgres
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  kind: 'linux'
  sku: {
    name: 'B1'
    tier: 'Basic'
    size: 'B1'
    family: 'B'
    capacity: 1
  }
  properties: {
    reserved: true
    perSiteScaling: false
    zoneRedundant: false
  }
  tags: {
    application: 'hindsight'
    managedBy: 'bicep'
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2025-07-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    features: {
      disableLocalAuth: false
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    retentionInDays: 30
  }
  tags: {
    application: 'hindsight'
    managedBy: 'bicep'
  }
}

resource monitorWorkspace 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: monitorWorkspaceName
  location: location
  properties: {
    publicNetworkAccess: 'Enabled'
  }
  tags: {
    application: 'hindsight'
    managedBy: 'bicep'
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    IngestionMode: 'LogAnalytics'
    WorkspaceResourceId: logAnalytics.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
  tags: {
    application: 'hindsight'
    managedBy: 'bicep'
    otelCollection: 'enabled'
  }
}

resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2024-03-11' = {
  name: dataCollectionEndpointName
  location: location
  properties: {
    description: 'Data Collection Endpoint for Hindsight OpenTelemetry traces.'
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
  tags: {
    application: 'hindsight'
    managedBy: 'bicep'
    otelCollection: 'enabled'
  }
}

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2024-03-11' = {
  name: dataCollectionRuleName
  location: location
  properties: {
    description: 'Direct OTLP trace ingestion for Hindsight through an OpenTelemetry Collector.'
    dataCollectionEndpointId: dataCollectionEndpoint.id
    references: {
      applicationInsights: [
        {
          resourceId: applicationInsights.id
          name: 'applicationInsightsResource'
        }
      ]
    }
    dataSources: {
      otelMetrics: [
        {
          streams: [
            'Custom-Metrics-Otel'
          ]
          enrichWithResourceAttributes: [
            '*'
          ]
          enrichWithReference: 'applicationInsightsResource'
          name: 'otelMetricsDataSource'
        }
      ]
      otelLogs: [
        {
          streams: [
            'Microsoft-OTel-Logs'
          ]
          enrichWithResourceAttributes: [
            '*'
          ]
          enrichWithReference: 'applicationInsightsResource'
          replaceResourceIdWithReference: true
          name: 'otelLogsDataSource'
        }
      ]
      otelTraces: [
        {
          streams: [
            'Microsoft-OTel-Traces-Spans'
            'Microsoft-OTel-Traces-Events'
            'Microsoft-OTel-Traces-Resources'
          ]
          enrichWithResourceAttributes: [
            '*'
          ]
          enrichWithReference: 'applicationInsightsResource'
          replaceResourceIdWithReference: true
          name: 'otelTracesDataSource'
        }
      ]
    }
    directDataSources: {
      otelMetrics: [
        {
          streams: [
            'Custom-Metrics-Otel'
          ]
          enrichWithResourceAttributes: [
            '*'
          ]
          enrichWithReference: 'applicationInsightsResource'
          name: 'otelMetricsDataSourceDirect'
        }
      ]
      otelLogs: [
        {
          streams: [
            'Microsoft-OTel-Logs'
          ]
          enrichWithResourceAttributes: [
            '*'
          ]
          enrichWithReference: 'applicationInsightsResource'
          replaceResourceIdWithReference: true
          name: 'otelLogsDataSourceDirect'
        }
      ]
      otelTraces: [
        {
          streams: [
            'Microsoft-OTel-Traces-Spans'
            'Microsoft-OTel-Traces-Events'
            'Microsoft-OTel-Traces-Resources'
          ]
          enrichWithResourceAttributes: [
            '*'
          ]
          enrichWithReference: 'applicationInsightsResource'
          replaceResourceIdWithReference: true
          name: 'otelTracesDataSourceDirect'
        }
      ]
    }
    destinations: {
      monitoringAccounts: [
        {
          accountResourceId: monitorWorkspace.id
          name: 'monitorWorkspace'
        }
      ]
      logAnalytics: [
        {
          workspaceResourceId: logAnalytics.id
          name: 'logAnalytics'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Custom-Metrics-Otel'
        ]
        destinations: [
          'monitorWorkspace'
        ]
      }
      {
        streams: [
          'Microsoft-OTel-Logs'
          'Microsoft-OTel-Traces-Spans'
          'Microsoft-OTel-Traces-Events'
          'Microsoft-OTel-Traces-Resources'
        ]
        destinations: [
          'logAnalytics'
        ]
      }
    ]
  }
  tags: {
    application: 'hindsight'
    managedBy: 'bicep'
    otelCollection: 'enabled'
  }
}

resource llmAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: llmAccountName
  location: aiLocation
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: llmAccountName
    disableLocalAuth: false
    publicNetworkAccess: 'Enabled'
  }
  tags: {
    application: 'hindsight'
    managedBy: 'bicep'
    purpose: 'llm-and-embeddings'
  }
}

resource llmDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: llmAccount
  name: llmDeploymentName
  sku: {
    name: 'GlobalStandard'
    capacity: 1
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: llmModelName
      version: llmModelVersion
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}

resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: llmAccount
  name: embeddingDeploymentName
  sku: {
    name: 'Standard'
    capacity: 1
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: embeddingModelName
      version: embeddingModelVersion
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}

resource rerankAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: rerankAccountName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: rerankAccountName
    disableLocalAuth: false
    publicNetworkAccess: 'Enabled'
  }
  tags: {
    application: 'hindsight'
    managedBy: 'bicep'
    purpose: 'reranker'
  }
}

resource rerankDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: rerankAccount
  name: rerankDeploymentName
  sku: {
    name: 'GlobalStandard'
    capacity: 1
  }
  properties: {
    model: {
      format: 'Cohere'
      name: rerankModelName
      version: rerankModelVersion
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}

var llmApiKey = listKeys(llmAccount.id, '2024-10-01').key1
var rerankApiKey = listKeys(rerankAccount.id, '2024-10-01').key1
var applicationInsightsConnectionString = reference(applicationInsights.id, '2020-02-02', 'full').properties.ConnectionString
var dataCollectionRuleDetails = reference(dataCollectionRule.id, '2024-03-11', 'full')
var dataCollectionEndpointDetails = reference(dataCollectionEndpoint.id, '2024-03-11', 'full')
var azureMonitorTracesEndpoint = '${dataCollectionEndpointDetails.properties.logsIngestion.endpoint}/datacollectionRules/${dataCollectionRuleDetails.properties.immutableId}/streams/${tracesStreamName}/otlp/v1/traces'

var collectorConfig = $$'''
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318
        auth:
          authenticator: bearertokenauth/server

processors:
  batch:

extensions:
  azure_auth:
    use_default: true
    scopes:
      - https://monitor.azure.com/.default
  bearertokenauth/server:
    token: ${env:OTEL_RECEIVER_TOKEN}

exporters:
  otlphttp/azuremonitor:
    traces_endpoint: $${azureMonitorTracesEndpoint}
    auth:
      authenticator: azure_auth

service:
  extensions:
    - azure_auth
    - bearertokenauth/server
  pipelines:
    traces:
      receivers:
        - otlp
      processors:
        - batch
      exporters:
        - otlphttp/azuremonitor
'''

resource collectorApp 'Microsoft.Web/sites@2023-12-01' = {
  name: collectorAppName
  location: location
  kind: 'app,linux,container'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${otelIdentity.id}': {}
    }
  }
  properties: {
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    clientAffinityEnabled: false
    clientCertEnabled: false
    enabled: true
    serverFarmId: plan.id
    siteConfig: {
      alwaysOn: true
      appCommandLine: 'sh -c \'echo "$OTEL_CONFIG_B64" | base64 -d > /tmp/otel-config.yaml && exec /otelcol-contrib --config=/tmp/otel-config.yaml\''
      appSettings: [
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name: 'WEBSITES_PORT'
          value: '4318'
        }
        {
          name: 'OTEL_CONFIG_B64'
          value: base64(collectorConfig)
        }
        {
          name: 'OTEL_RECEIVER_TOKEN'
          value: otelReceiverToken
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: otelIdentity.properties.clientId
        }
        {
          name: 'WEBSITES_CONTAINER_START_TIME_LIMIT'
          value: '1800'
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://index.docker.io'
        }
      ]
      ftpsState: 'Disabled'
      http20Enabled: true
      linuxFxVersion: 'DOCKER|${collectorImage}'
      minTlsVersion: '1.2'
    }
  }
  tags: {
    application: 'hindsight'
    managedBy: 'bicep'
    purpose: 'otel-collector'
  }
}

resource hindsightApp 'Microsoft.Web/sites@2023-12-01' = {
  name: appName
  location: location
  kind: 'app,linux,container'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${deploymentIdentity.id}': {}
    }
  }
  properties: {
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    clientAffinityEnabled: false
    clientCertEnabled: false
    enabled: true
    serverFarmId: plan.id
    siteConfig: {
      alwaysOn: true
      appSettings: [
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name: 'WEBSITES_PORT'
          value: '8888'
        }
        {
          name: 'WEBSITES_CONTAINER_START_TIME_LIMIT'
          value: '1800'
        }
        {
          name: 'HINDSIGHT_API_HOST'
          value: '0.0.0.0'
        }
        {
          name: 'HINDSIGHT_API_PORT'
          value: '8888'
        }
        {
          name: 'HINDSIGHT_API_LOG_FORMAT'
          value: 'json'
        }
        {
          name: 'HINDSIGHT_API_DATABASE_BACKEND'
          value: 'postgresql'
        }
        {
          name: 'HINDSIGHT_API_DATABASE_URL'
          value: postgresConnectionString
        }
        {
          name: 'HINDSIGHT_API_DB_POOL_MIN_SIZE'
          value: '1'
        }
        {
          name: 'HINDSIGHT_API_DB_POOL_MAX_SIZE'
          value: '5'
        }
        {
          name: 'HINDSIGHT_API_LLM_PROVIDER'
          value: 'openai-responses'
        }
        {
          name: 'HINDSIGHT_API_LLM_API_KEY'
          value: llmApiKey
        }
        {
          name: 'HINDSIGHT_API_LLM_MODEL'
          value: llmDeploymentName
        }
        {
          name: 'HINDSIGHT_API_LLM_BASE_URL'
          value: llmBaseUrl
        }
        {
          name: 'HINDSIGHT_API_LLM_REASONING_EFFORT'
          value: 'high'
        }
        {
          name: 'HINDSIGHT_API_LLM_TEMPERATURE'
          value: 'none'
        }
        {
          name: 'HINDSIGHT_API_EMBEDDINGS_PROVIDER'
          value: 'openai'
        }
        {
          name: 'HINDSIGHT_API_EMBEDDINGS_OPENAI_API_KEY'
          value: llmApiKey
        }
        {
          name: 'HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL'
          value: embeddingDeploymentName
        }
        {
          name: 'HINDSIGHT_API_EMBEDDINGS_OPENAI_BASE_URL'
          value: embeddingBaseUrl
        }
        {
          name: 'HINDSIGHT_API_RERANKER_PROVIDER'
          value: 'cohere'
        }
        {
          name: 'HINDSIGHT_API_RERANKER_COHERE_API_KEY'
          value: rerankApiKey
        }
        {
          name: 'HINDSIGHT_API_RERANKER_COHERE_MODEL'
          value: rerankDeploymentName
        }
        {
          name: 'HINDSIGHT_API_RERANKER_COHERE_BASE_URL'
          value: rerankBaseUrl
        }
        {
          name: 'HINDSIGHT_API_TENANT_EXTENSION'
          value: 'hindsight_api.extensions.builtin.tenant:ApiKeyTenantExtension'
        }
        {
          name: 'HINDSIGHT_API_TENANT_API_KEY'
          value: hindsightApiKey
        }
        {
          name: 'HINDSIGHT_API_OTEL_TRACES_ENABLED'
          value: 'true'
        }
        {
          name: 'HINDSIGHT_API_OTEL_EXPORTER_OTLP_ENDPOINT'
          value: collectorBaseUrl
        }
        {
          name: 'HINDSIGHT_API_OTEL_EXPORTER_OTLP_HEADERS'
          value: 'Authorization=Bearer ${otelReceiverToken}'
        }
        {
          name: 'HINDSIGHT_API_OTEL_SERVICE_NAME'
          value: 'hindsight-api'
        }
        {
          name: 'HINDSIGHT_API_OTEL_DEPLOYMENT_ENVIRONMENT'
          value: 'production'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsConnectionString
        }
        {
          name: 'OTEL_SERVICE_NAME'
          value: 'hindsight-api'
        }
        {
          name: 'OTEL_RESOURCE_ATTRIBUTES'
          value: 'cloud.provider=azure,cloud.region=westus2,service.namespace=hindsight'
        }
      ]
      ftpsState: 'Disabled'
      http20Enabled: true
      linuxFxVersion: 'DOCKER|${hindsightImage}'
      minTlsVersion: '1.2'
    }
  }
  tags: {
    application: 'hindsight'
    managedBy: 'bicep'
    purpose: 'api'
  }
}

output apiUrl string = 'https://${appName}.azurewebsites.net'
output collectorUrl string = collectorBaseUrl
output applicationInsightsId string = applicationInsights.id
output dataCollectionRuleId string = dataCollectionRule.id
output dataCollectionEndpointId string = dataCollectionEndpoint.id
output dataCollectionEndpoint string = dataCollectionEndpointDetails.properties.logsIngestion.endpoint
output dataCollectionRuleImmutableId string = dataCollectionRuleDetails.properties.immutableId
output postgresServerFullyQualifiedDomainName string = postgres.properties.fullyQualifiedDomainName
output llmEndpoint string = llmBaseUrl
output rerankEndpoint string = rerankBaseUrl
output embeddingEndpoint string = embeddingBaseUrl
