@description('Project name')
param projectName string

@description('Azure region')
param location string

@description('Custom domain (optional)')
param customDomain string = ''

var swaName = '${projectName}-hd-swa'

resource staticWebApp 'Microsoft.Web/staticSites@2023-12-01' = {
  name: swaName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {}
}

resource customDomainResource 'Microsoft.Web/staticSites/customDomains@2023-12-01' = if (!empty(customDomain)) {
  parent: staticWebApp
  name: customDomain
  properties: {}
}

output swaName string = staticWebApp.name
output swaHostname string = staticWebApp.properties.defaultHostname
output deploymentToken string = staticWebApp.listSecrets().properties.apiKey
