targetScope = 'subscription'

@description('Resource group that owns the Microsoft Foundry project.')
param resourceGroupName string

@description('Microsoft Foundry account name.')
param accountName string

@description('Microsoft Foundry project name.')
param projectName string

@description('Project capability host name.')
param capabilityHostName string = 'caphostproj'

@description('Cosmos DB project connection name.')
param cosmosDbConnectionName string

@description('Storage project connection name.')
param storageConnectionName string

@description('Search project connection name.')
param searchConnectionName string

module resources 'foundry-capability-host.resources.bicep' = {
  scope: resourceGroup(resourceGroupName)
  params: {
    accountName: accountName
    projectName: projectName
    capabilityHostName: capabilityHostName
    cosmosDbConnectionName: cosmosDbConnectionName
    storageConnectionName: storageConnectionName
    searchConnectionName: searchConnectionName
  }
}

output capabilityHostName string = resources.outputs.capabilityHostName
