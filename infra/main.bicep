targetScope = 'subscription'

@description('Azure region for the resource group, App Service, and monitoring resources.')
param location string = 'westus2'

@description('Resource group that owns the Hindsight deployment.')
param resourceGroupName string = 'rg-hindsight-wu2'

@description('Azure region for Azure OpenAI. GPT-5.6-luna is not listed for westus2, so the default is westus3.')
param aiLocation string = 'westus3'
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

@secure()
@description('API key required by Hindsight clients.')
param hindsightApiKey string

@secure()
@description('Bearer token accepted by the private OTLP collector endpoint.')
param otelReceiverToken string

@secure()
@description('PostgreSQL Flexible Server administrator password.')
param postgresAdminPassword string

resource deploymentResourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: resourceGroupName
  location: location
  tags: {
    application: 'hindsight'
    managedBy: 'bicep'
  }
}

module hindsightResources 'main-rg.bicep' = {
  name: 'hindsight-resources'
  scope: deploymentResourceGroup
  params: {
    location: location
    aiLocation: aiLocation
    hindsightApiKey: hindsightApiKey
    otelReceiverToken: otelReceiverToken
    postgresAdminPassword: postgresAdminPassword
    deploymentIdentityName: deploymentIdentityName
    otelIdentityName: otelIdentityName
    githubOwner: githubOwner
    githubRepository: githubRepository
    githubOwnerId: githubOwnerId
    githubRepositoryId: githubRepositoryId
    githubEnvironment: githubEnvironment
  }
}

output resourceGroupName string = deploymentResourceGroup.name
output apiUrl string = hindsightResources.outputs.apiUrl
output collectorUrl string = hindsightResources.outputs.collectorUrl
output applicationInsightsId string = hindsightResources.outputs.applicationInsightsId
output dataCollectionRuleId string = hindsightResources.outputs.dataCollectionRuleId
output dataCollectionEndpointId string = hindsightResources.outputs.dataCollectionEndpointId
output dataCollectionEndpoint string = hindsightResources.outputs.dataCollectionEndpoint
output dataCollectionRuleImmutableId string = hindsightResources.outputs.dataCollectionRuleImmutableId
output llmEndpoint string = hindsightResources.outputs.llmEndpoint
output rerankEndpoint string = hindsightResources.outputs.rerankEndpoint
output embeddingEndpoint string = hindsightResources.outputs.embeddingEndpoint
output postgresServerFqdn string = hindsightResources.outputs.postgresServerFqdn
