targetScope = 'subscription'

@description('Azure region for the resource group and managed identities.')
param location string = 'westus2'

@description('Resource group that owns the Hindsight deployment.')
param resourceGroupName string = 'rg-hindsight-wu2'

@description('User-assigned identity used by GitHub Actions for Azure deployments.')
param deploymentIdentityName string = 'id-hindsight-deploy-wu2'

@description('User-assigned identity used only by the OTLP collector.')
param otelIdentityName string = 'id-hindsight-otel-wu2'

@description('GitHub organization or user that owns the repository.')
param githubOwner string = 'pedropaulovc'

@description('GitHub repository name.')
param githubRepository string = 'hindsight'

@description('GitHub environment name used by the deployment workflow.')
param githubEnvironment string = 'prod'
resource resourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: resourceGroupName
  location: location
  tags: {
    application: 'hindsight'
    managedBy: 'bicep'
  }
}

module identityBootstrap 'bootstrap-rg.bicep' = {
  name: 'hindsight-identities'
  scope: resourceGroup
  params: {
    deploymentIdentityName: deploymentIdentityName
    otelIdentityName: otelIdentityName
    githubOwner: githubOwner
    githubRepository: githubRepository
    githubEnvironment: githubEnvironment
  }
}

output resourceGroupName string = resourceGroup.name
output deploymentIdentityName string = identityBootstrap.outputs.deploymentIdentityName
output deploymentIdentityResourceId string = identityBootstrap.outputs.deploymentIdentityResourceId
output deploymentClientId string = identityBootstrap.outputs.deploymentClientId
output deploymentPrincipalId string = identityBootstrap.outputs.deploymentPrincipalId
output otelIdentityName string = identityBootstrap.outputs.otelIdentityName
output otelIdentityResourceId string = identityBootstrap.outputs.otelIdentityResourceId
output otelClientId string = identityBootstrap.outputs.otelClientId
output otelPrincipalId string = identityBootstrap.outputs.otelPrincipalId
