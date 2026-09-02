targetScope = 'resourceGroup'

@description('Hindsight API App Service name.')
param appName string = 'app-hindsight-wu2'

@description('App Service plan that hosts the Hindsight API.')
param planName string = 'plan-hindsight-wu2'

@description('Public custom hostname for the Hindsight API.')
param apiHostname string = 'hindsight.vza.net'

var certificateName = 'cert-${replace(apiHostname, '.', '-')}'

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' existing = {
  name: planName
}

resource hindsightApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: appName
}

resource managedCertificate 'Microsoft.Web/certificates@2023-12-01' = {
  name: certificateName
  location: resourceGroup().location
  properties: {
    canonicalName: apiHostname
    domainValidationMethod: 'http-token'
    serverFarmId: appServicePlan.id
  }
}

// The preceding deployment creates the verified hostname binding.
resource hindsightHostnameBinding 'Microsoft.Web/sites/hostNameBindings@2023-12-01' = {
  parent: hindsightApp
  name: apiHostname
  properties: {
    customHostNameDnsRecordType: 'CName'
    hostNameType: 'Verified'
    siteName: hindsightApp.name
    sslState: 'SniEnabled'
    thumbprint: managedCertificate.properties.thumbprint
  }
}
