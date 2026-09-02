targetScope = 'resourceGroup'

@description('Azure region for the App Service and monitoring resources.')
param location string = 'westus2'

@description('Azure region for Azure OpenAI. GPT-5.6-luna is not listed for westus2, so the default is westus3.')
param aiLocation string = 'westus3'


@secure()
@description('API key required by Hindsight clients.')
param hindsightApiKey string

@secure()
@description('Bearer token accepted by the private OTLP collector endpoint.')
param otelReceiverToken string
@description('Email address that receives Azure Monitor 429 alerts.')
param rateLimitAlertEmail string = 'pedro@vezza.com.br'


@description('Azure OpenAI account name.')
param llmAccountName string = 'cog-hindsight-wu2'

@description('Azure AI Services account name used for reranking.')
param rerankAccountName string = 'rerank-hindsight-wu2'
@description('Restore the soft-deleted Azure OpenAI account during recovery.')
param restoreLlmAccount bool = false

@description('Restore the soft-deleted Azure AI Services account during recovery.')
param restoreRerankAccount bool = false

@description('Azure OpenAI deployment name for GPT-5.6-luna.')
param llmDeploymentName string = 'gpt-5-6-luna'
@description('GlobalStandard quota units allocated to the GPT-5.6-luna deployment. Each unit provides 1,000 TPM and 1 RPM; 1,000 units provide 1,000,000 TPM and 1,000 RPM.')
param llmDeploymentCapacity int = 1000


@description('Azure OpenAI deployment name for text-embedding-3-small.')
param embeddingDeploymentName string = 'embedding-3-small'

@description('Azure AI Services deployment name for Cohere reranking.')
param rerankDeploymentName string = 'cohere-rerank-v4-0-pro'

@description('App Service plan name.')
param planName string = 'plan-hindsight-wu2'

@description('Hindsight API App Service name.')
param appName string = 'app-hindsight-wu2'
@description('Public custom hostname for the Hindsight API.')
param apiHostname string = 'hindsight.vza.net'

@description('PostgreSQL Flexible Server name.')
param postgresServerName string = 'pg-hindsight-wu2'

@description('PostgreSQL database name used by Hindsight.')
param postgresDatabaseName string = 'hindsight'

@description('PostgreSQL Flexible Server administrator login.')
param postgresAdminLogin string = 'hindsightadmin'

@secure()
@description('PostgreSQL Flexible Server administrator password.')
param postgresAdminPassword string

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
@description('User-assigned identity used by GitHub Actions for Azure deployments.')
param deploymentIdentityName string = 'id-hindsight-deploy-wu2'

@description('User-assigned identity used only by the OTLP collector.')
param otelIdentityName string = 'id-hindsight-otel-wu2'

@description('GitHub organization or user that owns the repository.')
param githubOwner string = 'pedropaulovc'

@description('GitHub repository name.')
param githubRepository string = 'hindsight'

@description('Immutable GitHub owner ID used by the repository subject claim.')
param githubOwnerId string = '577970'

@description('Immutable GitHub repository ID used by the repository subject claim.')
param githubRepositoryId string = '1353841016'

@description('GitHub environment name used by the deployment workflow.')
param githubEnvironment string = 'prod'



var hindsightImage = 'ghcr.io/vectorize-io/hindsight-api:0.9.2-slim'
var collectorImage = 'otel/opentelemetry-collector-contrib:0.132.0'
var llmModelName = 'gpt-5.6-luna'
var llmModelVersion = '2026-07-09'
var embeddingModelName = 'text-embedding-3-small'
var embeddingModelVersion = '1'
var rerankModelName = 'Cohere-rerank-v4.0-pro'
var rerankModelVersion = '1'
var llmBaseUrl = 'https://${llmAccountName}.openai.azure.com/openai/v1'
var embeddingBaseUrl = 'https://${llmAccountName}.openai.azure.com/openai/deployments/${embeddingDeploymentName}?api-version=2024-10-21'
var rerankBaseUrl = 'https://${rerankAccountName}.services.ai.azure.com/providers/cohere/v2/rerank'
var collectorBaseUrl = 'https://${collectorAppName}.azurewebsites.net'
var virtualNetworkName = 'vnet-hindsight-wu2'
var appServiceSubnetName = 'snet-appservice'
var postgresSubnetName = 'snet-postgres'
var postgresPrivateDnsZoneName = 'private.postgres.database.azure.com'
var postgresServerFqdn = '${postgresServerName}.postgres.database.azure.com'
var postgresConnectionString = 'postgresql://${postgresAdminLogin}:${uriComponent(postgresAdminPassword)}@${postgresServerFqdn}:5432/${postgresDatabaseName}?sslmode=require'
// Azure's OTLP ingestion routes logs and traces to the DCR streams below.
var logsStreamName = 'Microsoft-OTLP-Logs'
var tracesStreamName = 'Microsoft-OTLP-Traces'



resource deploymentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: deploymentIdentityName
  location: location
  tags: {
    application: 'hindsight'
    purpose: 'github-actions-deployment'
  }
}

resource otelIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: otelIdentityName
  location: location
  tags: {
    application: 'hindsight'
    purpose: 'otel-collector'
  }
}

resource githubFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  name: 'github-prod-environment'
  parent: deploymentIdentity
  properties: {
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:${githubOwner}@${githubOwnerId}/${githubRepository}@${githubRepositoryId}:environment:${githubEnvironment}'
  }
}

var contributorRoleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var monitoringMetricsPublisherRoleDefinitionId = '3913510d-42f4-4e42-8a64-420c390055eb'

resource contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, deploymentIdentityName, contributorRoleDefinitionId)
  properties: {
    principalId: deploymentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleDefinitionId)
  }
}
var roleBasedAccessControlAdministratorRoleDefinitionId = 'f58310d9-a9f6-439a-9e8d-f62e7b41a168'

resource deploymentRoleAdministratorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, deploymentIdentityName, roleBasedAccessControlAdministratorRoleDefinitionId)
  properties: {
    principalId: deploymentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleBasedAccessControlAdministratorRoleDefinitionId)
  }
}
var managedIdentityOperatorRoleDefinitionId = 'f1a07417-d97a-45cb-824c-7a7467783830'

resource deploymentIdentityOperatorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(otelIdentity.id, deploymentIdentityName, managedIdentityOperatorRoleDefinitionId)
  scope: otelIdentity
  properties: {
    principalId: deploymentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', managedIdentityOperatorRoleDefinitionId)
  }
}
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.20.0.0/16'
      ]
    }
  }
  tags: {
    application: 'hindsight'
    managedBy: 'bicep'
  }
}

resource appServiceSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: virtualNetwork
  name: appServiceSubnetName
  properties: {
    addressPrefix: '10.20.0.0/26'
    delegations: [
      {
        name: 'appService'
        properties: {
          serviceName: 'Microsoft.Web/serverFarms'
        }
      }
    ]
  }
}

resource postgresSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: virtualNetwork
  name: postgresSubnetName
  properties: {
    addressPrefix: '10.20.1.0/28'
    delegations: [
      {
        name: 'postgres'
        properties: {
          serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
        }
      }
    ]
  }
}

resource postgresPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: postgresPrivateDnsZoneName
  location: 'global'
  tags: {
    application: 'hindsight'
    managedBy: 'bicep'
  }
}

resource postgresPrivateDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: postgresPrivateDnsZone
  name: virtualNetworkName
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
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

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: postgresServerName
  location: location
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  dependsOn: [
    postgresPrivateDnsLink
  ]
  properties: {
    administratorLogin: postgresAdminLogin
    administratorLoginPassword: postgresAdminPassword
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    network: {
      delegatedSubnetResourceId: postgresSubnet.id
      privateDnsZoneArmResourceId: postgresPrivateDnsZone.id
      publicNetworkAccess: 'Disabled'
    }
    storage: {
      autoGrow: 'Disabled'
      storageSizeGB: 32
      type: 'Premium_LRS'
    }
    version: '16'
  }
  tags: {
    application: 'hindsight'
    managedBy: 'bicep'
    purpose: 'database'
  }
}

resource postgresExtensions 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: postgresServer
  name: 'azure.extensions'
  properties: {
    source: 'user-override'
    value: 'vector,pg_trgm'
  }
}

resource postgresDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: postgresServer
  name: postgresDatabaseName
  dependsOn: [
    postgresExtensions
  ]
  properties: {
    charset: 'UTF8'
    collation: 'en_US.UTF8'
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
    description: 'Data Collection Endpoint for Hindsight OpenTelemetry telemetry.'
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
    description: 'Direct OTLP telemetry ingestion for Hindsight through an OpenTelemetry Collector.'
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
resource collectorMetricsPublisherAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataCollectionRule.id, otelIdentity.id, monitoringMetricsPublisherRoleDefinitionId)
  scope: dataCollectionRule
  properties: {
    principalId: otelIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleDefinitionId)
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
    restore: restoreLlmAccount
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
  dependsOn: [
    embeddingDeployment
  ]
  sku: {
    name: 'GlobalStandard'
    capacity: llmDeploymentCapacity
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
    name: 'GlobalStandard'
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
    restore: restoreRerankAccount
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

var llmApiKey = llmAccount.listKeys('2024-10-01').key1
var rerankApiKey = rerankAccount.listKeys('2024-10-01').key1
var applicationInsightsConnectionString = applicationInsights.properties.ConnectionString
var dataCollectionEndpointUrl = dataCollectionEndpoint.properties.logsIngestion.endpoint
var dataCollectionRuleImmutableId = dataCollectionRule.properties.immutableId
var azureMonitorTracesEndpoint = '${dataCollectionEndpointUrl}/datacollectionRules/${dataCollectionRuleImmutableId}/streams/${tracesStreamName}/otlp/v1/traces'
var azureMonitorLogsEndpoint = '${dataCollectionEndpointUrl}/datacollectionRules/${dataCollectionRuleImmutableId}/streams/${logsStreamName}/otlp/v1/logs'

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
  azureauth:
    use_default: true
    scopes:
      - https://monitor.azure.com/.default
  bearertokenauth/server:
    token: ${env:OTEL_RECEIVER_TOKEN}

exporters:
  otlphttp/azuremonitor:
    traces_endpoint: $${azureMonitorTracesEndpoint}
    logs_endpoint: $${azureMonitorLogsEndpoint}
    auth:
      authenticator: azureauth

service:
  extensions:
    - azureauth
    - bearertokenauth/server
  pipelines:
    traces:
      receivers:
        - otlp
      processors:
        - batch
      exporters:
        - otlphttp/azuremonitor
    logs:
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
  dependsOn: [
    deploymentIdentityOperatorAssignment
  ]
  properties: {
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    clientAffinityEnabled: false
    clientCertEnabled: false
    enabled: true
    serverFarmId: plan.id
    siteConfig: {
      alwaysOn: true
      appCommandLine: '--config=env:OTEL_CONFIG'
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
          name: 'OTEL_CONFIG'
          value: collectorConfig
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
    type: 'None'
  }
  dependsOn: [
    postgresDatabase
  ]
  properties: {
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    clientAffinityEnabled: false
    clientCertEnabled: false
    enabled: true
    serverFarmId: plan.id
    virtualNetworkSubnetId: appServiceSubnet.id
    siteConfig: {
      alwaysOn: true
      appSettings: [
        // The managed PostgreSQL server owns the database; local App Service
        // storage is disabled because no application data belongs on the container.
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
          name: 'HINDSIGHT_API_WORKER_ID'
          value: 'hindsight-local'
        }
        {
          name: 'HINDSIGHT_API_AUDIT_LOG_ENABLED'
          value: 'true'
        }
        {
          name: 'HINDSIGHT_API_CONSOLIDATION_LLM_TIMEOUT'
          value: '1200'
        }
        {
          name: 'HINDSIGHT_API_REFLECT_LLM_TIMEOUT'
          value: '1200'
        }
        {
          name: 'HINDSIGHT_API_REFLECT_WALL_TIMEOUT'
          value: '1200'
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
          value: embeddingModelName
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
          value: 'cloud.provider=azure,cloud.region=${location},service.namespace=hindsight'
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

resource hindsightAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'hindsight-app-to-log-analytics'
  scope: hindsightApp
  properties: {
    logAnalyticsDestinationType: 'Dedicated'
    workspaceId: logAnalytics.id
    logs: [
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
      }
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServicePlatformLogs'
        enabled: true
      }
    ]
  }
}

resource collectorAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'otel-collector-to-log-analytics'
  scope: collectorApp
  properties: {
    logAnalyticsDestinationType: 'Dedicated'
    workspaceId: logAnalytics.id
    logs: [
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
      }
      {
        category: 'AppServicePlatformLogs'
        enabled: true
      }
    ]
  }
}

resource rateLimitActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-hindsight-429'
  location: 'global'
  properties: {
    enabled: true
    groupShortName: 'hindsight429'
    emailReceivers: [
      {
        name: 'Pedro'
        emailAddress: rateLimitAlertEmail
        useCommonAlertSchema: true
      }
    ]
  }
  tags: {
    application: 'hindsight'
    managedBy: 'bicep'
    purpose: 'rate-limit-alerting'
  }
}

resource llmRateLimitAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-hindsight-llm-429'
  location: 'global'
  properties: {
    description: 'Alerts when an Azure OpenAI model request returns HTTP 429.'
    severity: 2
    enabled: true
    scopes: [
      llmAccount.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    autoMitigate: true
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'AzureModelRequests429'
          criterionType: 'StaticThresholdCriterion'
          metricName: 'AzureOpenAIRequests'
          metricNamespace: 'Microsoft.CognitiveServices/accounts'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Total'
          skipMetricValidation: false
          dimensions: [
            {
              name: 'StatusCode'
              operator: 'Include'
              values: [
                '429'
              ]
            }
          ]
        }
      ]
    }
    actions: [
      {
        actionGroupId: rateLimitActionGroup.id
      }
    ]
  }
  tags: {
    application: 'hindsight'
    managedBy: 'bicep'
    purpose: 'rate-limit-alerting'
  }
}

resource rerankRateLimitAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-hindsight-rerank-429'
  location: 'global'
  properties: {
    description: 'Alerts when an Azure AI Services reranker request returns HTTP 429.'
    severity: 2
    enabled: true
    scopes: [
      rerankAccount.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    autoMitigate: true
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'RerankModelRequests429'
          criterionType: 'StaticThresholdCriterion'
          metricName: 'ModelRequests'
          metricNamespace: 'Microsoft.CognitiveServices/accounts'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Total'
          skipMetricValidation: false
          dimensions: [
            {
              name: 'StatusCode'
              operator: 'Include'
              values: [
                '429'
              ]
            }
          ]
        }
      ]
    }
    actions: [
      {
        actionGroupId: rateLimitActionGroup.id
      }
    ]
  }
  tags: {
    application: 'hindsight'
    managedBy: 'bicep'
    purpose: 'rate-limit-alerting'
  }
}

output apiUrl string = 'https://${apiHostname}'
output apiHostname string = apiHostname
output apiHostnameCnameTarget string = '${appName}.azurewebsites.net'
output apiHostnameVerificationId string = hindsightApp.properties.customDomainVerificationId
output collectorUrl string = collectorBaseUrl
output applicationInsightsId string = applicationInsights.id
output dataCollectionRuleId string = dataCollectionRule.id
output dataCollectionEndpointId string = dataCollectionEndpoint.id
output dataCollectionEndpoint string = dataCollectionEndpointUrl
output dataCollectionRuleImmutableId string = dataCollectionRuleImmutableId
output llmEndpoint string = llmBaseUrl
output rerankEndpoint string = rerankBaseUrl
output embeddingEndpoint string = embeddingBaseUrl
output postgresServerFqdn string = postgresServerFqdn
output hindsightAppDiagnosticsId string = hindsightAppDiagnostics.id
output collectorAppDiagnosticsId string = collectorAppDiagnostics.id
output rateLimitActionGroupId string = rateLimitActionGroup.id
output llmRateLimitAlertId string = llmRateLimitAlert.id
output rerankRateLimitAlertId string = rerankRateLimitAlert.id
