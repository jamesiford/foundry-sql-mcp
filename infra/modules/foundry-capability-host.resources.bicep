targetScope = 'resourceGroup'

@description('Microsoft Foundry account name.')
param accountName string

@description('Microsoft Foundry project name.')
param projectName string

@description('Project capability host name.')
param capabilityHostName string

@description('Cosmos DB project connection name.')
param cosmosDbConnectionName string

@description('Storage project connection name.')
param storageConnectionName string

@description('Search project connection name.')
param searchConnectionName string

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: accountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' existing = {
  parent: account
  name: projectName
}

resource capabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = {
  parent: project
  name: capabilityHostName
  properties: {
    #disable-next-line BCP037
    capabilityHostKind: 'Agents'
    storageConnections: [
      storageConnectionName
    ]
    threadStorageConnections: [
      cosmosDbConnectionName
    ]
    vectorStoreConnections: [
      searchConnectionName
    ]
  }
}

output capabilityHostName string = capabilityHost.name
