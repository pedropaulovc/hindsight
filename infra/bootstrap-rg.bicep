targetScope = 'resourceGroup'

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

var contributorRoleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var managedIdentityOperatorRoleDefinitionId = 'f1a07417-d97a-45cb-824c-7a7467783830'
var monitoringMetricsPublisherRoleDefinitionId = '3913510d-42f4-4e42-8a64-420c390055eb'

resource deploymentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: deploymentIdentityName
  location: resourceGroup().location
  tags: {
    application: 'hindsight'
    purpose: 'github-deployment'
  }
}

resource otelIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: otelIdentityName
  location: resourceGroup().location
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
    subject: 'repo:${githubOwner}/${githubRepository}:environment:${githubEnvironment}'
  }
}

resource contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, deploymentIdentityName, contributorRoleDefinitionId)
  properties: {
    principalId: deploymentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleDefinitionId)
  }
}

resource otelMetricsPublisherRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, otelIdentityName, monitoringMetricsPublisherRoleDefinitionId)
  properties: {
    principalId: otelIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleDefinitionId)
  }
}

resource deploymentIdentityOperatorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(otelIdentity.id, deploymentIdentityName, managedIdentityOperatorRoleDefinitionId)
  scope: otelIdentity
  properties: {
    principalId: deploymentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', managedIdentityOperatorRoleDefinitionId)
  }
}

output deploymentIdentityName string = deploymentIdentity.name
output deploymentIdentityResourceId string = deploymentIdentity.id
output deploymentClientId string = deploymentIdentity.properties.clientId
output deploymentPrincipalId string = deploymentIdentity.properties.principalId
output otelIdentityName string = otelIdentity.name
output otelIdentityResourceId string = otelIdentity.id
output otelClientId string = otelIdentity.properties.clientId
output otelPrincipalId string = otelIdentity.properties.principalId
