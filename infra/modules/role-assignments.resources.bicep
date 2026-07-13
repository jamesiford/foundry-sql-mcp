targetScope = 'resourceGroup'

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

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' existing = {
  name: cosmosDbAccountName
}

resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' existing = {
  name: searchServiceName
}

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: foundryAccountName
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' existing = {
  parent: foundryAccount
  name: foundryProjectName
}

var storageBlobDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var storageBlobDataOwnerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
var cosmosDbOperatorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '230815da-be43-4aae-9cb4-875f7bd000aa')
var searchIndexDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
var searchServiceContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
var foundryUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '53ca6127-db72-4b80-b1b0-d745d6d5456d')
var cosmosDataContributorRoleId = '${cosmosDbAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
var storageOwnerCondition = '((!(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/read\'}) AND !(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/filter/action\'}) AND !(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/write\'})) OR (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWithIgnoreCase \'${projectWorkspaceId}\' AND @Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringLikeIgnoreCase \'*-azureml-agent\'))'

resource storageContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(projectPrincipalId, storageBlobDataContributorRoleId, storageAccount.id)
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: storageBlobDataContributorRoleId
  }
}

resource storageOwnerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(projectPrincipalId, storageBlobDataOwnerRoleId, storageAccount.id, projectWorkspaceId)
  properties: {
    condition: storageOwnerCondition
    conditionVersion: '2.0'
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: storageBlobDataOwnerRoleId
  }
}

resource cosmosOperatorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: cosmosDbAccount
  name: guid(projectPrincipalId, cosmosDbOperatorRoleId, cosmosDbAccount.id)
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: cosmosDbOperatorRoleId
  }
}

resource cosmosDataAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-12-01-preview' = {
  parent: cosmosDbAccount
  name: guid(projectWorkspaceId, projectPrincipalId, cosmosDataContributorRoleId)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: cosmosDataContributorRoleId
    scope: cosmosDbAccount.id
  }
}

resource searchIndexContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: searchService
  name: guid(projectPrincipalId, searchIndexDataContributorRoleId, searchService.id)
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: searchIndexDataContributorRoleId
  }
}

resource searchServiceContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: searchService
  name: guid(projectPrincipalId, searchServiceContributorRoleId, searchService.id)
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: searchServiceContributorRoleId
  }
}

resource foundryUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundryProject
  name: guid(deployerPrincipalId, foundryUserRoleId, foundryProject.id)
  properties: {
    principalId: deployerPrincipalId
    principalType: 'User'
    roleDefinitionId: foundryUserRoleId
  }
}

output assignmentNames object = {
  storageContributor: storageContributorAssignment.name
  storageOwner: storageOwnerAssignment.name
  cosmosOperator: cosmosOperatorAssignment.name
  cosmosDataContributor: cosmosDataAssignment.name
  searchIndexContributor: searchIndexContributorAssignment.name
  searchServiceContributor: searchServiceContributorAssignment.name
  foundryUser: foundryUserAssignment.name
}
