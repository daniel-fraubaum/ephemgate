targetScope = 'subscription'

@description('Project name used for all resource names')
param projectName string

@description('Azure region for all resources')
param location string = 'germanywestcentral'

@description('Entra ID Client ID for Self-Service App Registration')
param entraClientIdSS string

@description('Entra ID Client ID for Helpdesk App Registration')
param entraClientIdHD string

@description('Entra ID Tenant ID')
param entraTenantId string

@description('Azure region for Static Web Apps (must be a supported SWA region)')
param swaLocation string = 'westeurope'

@description('Custom domain for Self-Service Static Web App (optional)')
param customDomainSS string = ''

@description('Custom domain for Helpdesk Static Web App (optional)')
param customDomainHD string = ''

@description('Resource group name')
param resourceGroupName string = 'rg-${projectName}'

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    projectName: projectName
    location: location
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    projectName: projectName
    location: location
  }
}

module appServicePlan 'modules/appServicePlan.bicep' = {
  name: 'appServicePlan'
  scope: rg
  params: {
    projectName: projectName
    location: location
  }
}

module swaSelfService 'modules/staticwebapp-selfservice.bicep' = {
  name: 'swa-selfservice'
  scope: rg
  params: {
    projectName: projectName
    location: swaLocation
    customDomain: customDomainSS
  }
}

module swaHelpdesk 'modules/staticwebapp-helpdesk.bicep' = {
  name: 'swa-helpdesk'
  scope: rg
  params: {
    projectName: projectName
    location: swaLocation
    customDomain: customDomainHD
  }
}

module funcSelfService 'modules/functionapp-selfservice.bicep' = {
  name: 'func-selfservice'
  scope: rg
  params: {
    projectName: projectName
    location: location
    appServicePlanId: appServicePlan.outputs.planId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    storageAccountName: storage.outputs.storageAccountName
    entraClientId: entraClientIdSS
    entraTenantId: entraTenantId
  }
}

module funcHelpdesk 'modules/functionapp-helpdesk.bicep' = {
  name: 'func-helpdesk'
  scope: rg
  params: {
    projectName: projectName
    location: location
    appServicePlanId: appServicePlan.outputs.planId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    storageAccountName: storage.outputs.storageAccountName
    entraClientId: entraClientIdHD
    entraTenantId: entraTenantId
  }
}

output resourceGroupName string = rg.name
output storageAccountName string = storage.outputs.storageAccountName
output funcSelfServiceName string = funcSelfService.outputs.functionAppName
output funcSelfServiceHostname string = funcSelfService.outputs.functionAppHostname
output funcSelfServicePrincipalId string = funcSelfService.outputs.principalId
output funcHelpdeskName string = funcHelpdesk.outputs.functionAppName
output funcHelpdeskHostname string = funcHelpdesk.outputs.functionAppHostname
output funcHelpdeskPrincipalId string = funcHelpdesk.outputs.principalId
output swaSelfServiceName string = swaSelfService.outputs.swaName
output swaSelfServiceHostname string = swaSelfService.outputs.swaHostname
output swaSelfServiceDeploymentToken string = swaSelfService.outputs.deploymentToken
output swaHelpdeskName string = swaHelpdesk.outputs.swaName
output swaHelpdeskHostname string = swaHelpdesk.outputs.swaHostname
output swaHelpdeskDeploymentToken string = swaHelpdesk.outputs.deploymentToken
