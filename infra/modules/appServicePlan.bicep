@description('Project name')
param projectName string

@description('Azure region')
param location string

var planName = '${projectName}-plan'

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  kind: 'functionapp'
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
}

output planId string = appServicePlan.id
output planName string = appServicePlan.name
