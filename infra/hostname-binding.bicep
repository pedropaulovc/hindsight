targetScope = 'resourceGroup'

@description('Hindsight API App Service name.')
param appName string = 'app-hindsight-wu2'

@description('Public custom hostname for the Hindsight API.')
param apiHostname string = 'hindsight.vza.net'

resource hindsightApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: appName
}

resource hindsightHostnameBinding 'Microsoft.Web/sites/hostNameBindings@2023-12-01' = {
  parent: hindsightApp
  name: apiHostname
  properties: {
    customHostNameDnsRecordType: 'CName'
    hostNameType: 'Verified'
    siteName: hindsightApp.name
  }
}
