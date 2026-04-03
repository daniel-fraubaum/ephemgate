@description('Project name')
param projectName string

@description('Azure region')
param location string

var cleanProjectName = replace(replace(projectName, '-', ''), '_', '')
var storageAccountName = toLower('${take(cleanProjectName, 9)}st${uniqueString(resourceGroup().id)}')

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource auditTableSS 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: 'TapAuditSelfService'
}

resource auditTableHD 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: 'TapAuditHelpdesk'
}

resource rateLimitTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: 'RateLimitTracking'
}

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
