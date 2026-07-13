targetScope = 'subscription'

@description('Resource group that owns Microsoft Foundry dependencies.')
param resourceGroupName string

@description('Foundry project managed identity principal ID.')
param projectPrincipalId string

@description('Foundry project workspace ID.')
param projectWorkspaceId string

@description('Azure Storage account name.')
param storageAccountName string

@description('Azure Cosmos DB account name.')
param cosmosDbAccountName string

@description('Azure AI Search service name.')
param searchServiceName string

@description('Microsoft Foundry account name.')
param foundryAccountName string

@description('Microsoft Foundry project name.')
param foundryProjectName string

@description('Object ID of the deployment user who needs Foundry project access.')
param deployerPrincipalId string

module resources 'role-assignments.resources.bicep' = {
  scope: resourceGroup(resourceGroupName)
  params: {
    projectPrincipalId: projectPrincipalId
    projectWorkspaceId: projectWorkspaceId
    storageAccountName: storageAccountName
    cosmosDbAccountName: cosmosDbAccountName
    searchServiceName: searchServiceName
    foundryAccountName: foundryAccountName
    foundryProjectName: foundryProjectName
    deployerPrincipalId: deployerPrincipalId
  }
}

output assignmentNames object = resources.outputs.assignmentNames
