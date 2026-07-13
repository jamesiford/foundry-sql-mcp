targetScope = 'subscription'

@description('Azure region for Microsoft Foundry resources.')
param location string

@description('Resource group that owns Microsoft Foundry resources.')
param resourceGroupName string

@description('Microsoft Foundry account name.')
param accountName string

@description('Microsoft Foundry project name.')
param projectName string

@description('Display name for the Microsoft Foundry project.')
param projectDisplayName string

@description('Description for the Microsoft Foundry project.')
param projectDescription string

@description('Azure Storage account name required by Standard Agent Setup.')
param storageAccountName string

@description('Azure Cosmos DB account name required by Standard Agent Setup.')
param cosmosDbAccountName string

@description('Azure AI Search service name required by Standard Agent Setup.')
param searchServiceName string

@description('Model deployment name.')
param modelDeploymentName string

@description('Model catalog name.')
param modelName string

@description('Model format.')
param modelFormat string = 'OpenAI'

@description('Model version.')
param modelVersion string

@description('Model deployment SKU.')
param modelSkuName string = 'GlobalStandard'

@description('Model deployment capacity.')
@minValue(1)
param modelCapacity int = 1

@description('Dedicated Foundry Agent Service subnet ID.')
param agentSubnetId string

@description('Subnet ID used for private endpoints.')
param privateEndpointSubnetId string

@description('Private DNS zone IDs created by the networking module.')
param privateDnsZoneIds object

@description('Application Insights resource ID for agent tracing.')
param applicationInsightsId string

@description('Application Insights connection string for the Foundry connection.')
param applicationInsightsConnectionString string

@description('Tags applied to Microsoft Foundry resources.')
param tags object = {}

module resources 'foundry.resources.bicep' = {
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    accountName: accountName
    projectName: projectName
    projectDisplayName: projectDisplayName
    projectDescription: projectDescription
    storageAccountName: storageAccountName
    cosmosDbAccountName: cosmosDbAccountName
    searchServiceName: searchServiceName
    modelDeploymentName: modelDeploymentName
    modelName: modelName
    modelFormat: modelFormat
    modelVersion: modelVersion
    modelSkuName: modelSkuName
    modelCapacity: modelCapacity
    agentSubnetId: agentSubnetId
    privateEndpointSubnetId: privateEndpointSubnetId
    privateDnsZoneIds: privateDnsZoneIds
    applicationInsightsId: applicationInsightsId
    applicationInsightsConnectionString: applicationInsightsConnectionString
    tags: tags
  }
}

output accountId string = resources.outputs.accountId
output accountName string = resources.outputs.accountName
output accountEndpoint string = resources.outputs.accountEndpoint
output projectId string = resources.outputs.projectId
output projectName string = resources.outputs.projectName
output projectPrincipalId string = resources.outputs.projectPrincipalId
output projectWorkspaceId string = resources.outputs.projectWorkspaceId
output projectEndpoint string = resources.outputs.projectEndpoint
output storageAccountId string = resources.outputs.storageAccountId
output storageAccountName string = resources.outputs.storageAccountName
output cosmosDbAccountId string = resources.outputs.cosmosDbAccountId
output cosmosDbAccountName string = resources.outputs.cosmosDbAccountName
output searchServiceId string = resources.outputs.searchServiceId
output searchServiceName string = resources.outputs.searchServiceName
output cosmosDbConnectionName string = resources.outputs.cosmosDbConnectionName
output storageConnectionName string = resources.outputs.storageConnectionName
output searchConnectionName string = resources.outputs.searchConnectionName
