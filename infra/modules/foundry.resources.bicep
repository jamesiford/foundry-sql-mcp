targetScope = 'resourceGroup'

@description('Azure region for Microsoft Foundry resources.')
param location string

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
param modelFormat string

@description('Model version.')
param modelVersion string

@description('Model deployment SKU.')
param modelSkuName string

@description('Model deployment capacity.')
param modelCapacity int

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
param tags object

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_ZRS'
  }
  tags: tags
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' = {
  name: cosmosDbAccountName
  location: location
  kind: 'GlobalDocumentDB'
  tags: tags
  properties: {
    databaseAccountOfferType: 'Standard'
    disableLocalAuth: true
    enableAutomaticFailover: false
    enableFreeTier: false
    enableMultipleWriteLocations: false
    publicNetworkAccess: 'Disabled'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
  }
}

resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: searchServiceName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'standard'
  }
  tags: tags
  properties: {
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
    disableLocalAuth: false
    hostingMode: 'default'
    networkRuleSet: {
      bypass: 'None'
      ipRules: []
    }
    partitionCount: 1
    publicNetworkAccess: 'disabled'
    replicaCount: 1
    semanticSearch: 'disabled'
  }
}

#disable-next-line BCP036
resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: accountName
  location: location
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'S0'
  }
  tags: tags
  properties: {
    allowProjectManagement: true
    customSubDomainName: accountName
    disableLocalAuth: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
    networkInjections: [
      {
        scenario: 'agent'
        subnetArmId: agentSubnetId
        useMicrosoftManagedNetwork: false
      }
    ]
    publicNetworkAccess: 'Disabled'
  }
}

#disable-next-line BCP081
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: account
  name: modelDeploymentName
  sku: {
    name: modelSkuName
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: modelFormat
      name: modelName
      version: modelVersion
    }
  }
}

resource appInsightsConnection 'Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview' = {
  parent: account
  name: '${accountName}-appinsights'
  properties: {
    authType: 'ApiKey'
    category: 'AppInsights'
    credentials: {
      key: applicationInsightsConnectionString
    }
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: applicationInsightsId
    }
    target: applicationInsightsId
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: account
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    description: projectDescription
    displayName: projectDisplayName
  }

  resource cosmosDbConnection 'connections@2025-04-01-preview' = {
    name: cosmosDbAccountName
    properties: {
      authType: 'AAD'
      category: 'CosmosDB'
      metadata: {
        ApiType: 'Azure'
        ResourceId: cosmosDbAccount.id
        location: cosmosDbAccount.location
      }
      target: cosmosDbAccount.properties.documentEndpoint
    }
  }

  resource storageConnection 'connections@2025-04-01-preview' = {
    name: storageAccountName
    properties: {
      authType: 'AAD'
      category: 'AzureStorageAccount'
      metadata: {
        ApiType: 'Azure'
        ResourceId: storageAccount.id
        location: storageAccount.location
      }
      target: storageAccount.properties.primaryEndpoints.blob
    }
  }

  resource searchConnection 'connections@2025-04-01-preview' = {
    name: searchServiceName
    properties: {
      authType: 'AAD'
      category: 'CognitiveSearch'
      metadata: {
        ApiType: 'Azure'
        ResourceId: searchService.id
        location: searchService.location
      }
      #disable-next-line no-hardcoded-env-urls
      target: 'https://${searchServiceName}.search.windows.net'
    }
  }
}

resource privateEndpoints 'Microsoft.Network/privateEndpoints@2024-05-01' = [for item in [
  {
    name: 'foundry'
    resourceId: account.id
    groupIds: [
      'account'
    ]
  }
  {
    name: 'search'
    resourceId: searchService.id
    groupIds: [
      'searchService'
    ]
  }
  {
    name: 'cosmos'
    resourceId: cosmosDbAccount.id
    groupIds: [
      'Sql'
    ]
  }
  {
    name: 'storage'
    resourceId: storageAccount.id
    groupIds: [
      'blob'
    ]
  }
]: {
  name: 'pe-${item.name}-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: item.name
        properties: {
          privateLinkServiceId: item.resourceId
          groupIds: item.groupIds
        }
      }
    ]
  }
}]

resource foundryDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoints[0]
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'foundry-services'
        properties: {
          privateDnsZoneId: privateDnsZoneIds.foundryServices
        }
      }
      {
        name: 'openai'
        properties: {
          privateDnsZoneId: privateDnsZoneIds.openAi
        }
      }
      {
        name: 'cognitive-services'
        properties: {
          privateDnsZoneId: privateDnsZoneIds.cognitiveServices
        }
      }
    ]
  }
}

resource searchDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoints[1]
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'search'
        properties: {
          privateDnsZoneId: privateDnsZoneIds.search
        }
      }
    ]
  }
}

resource cosmosDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoints[2]
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'cosmos-sql'
        properties: {
          privateDnsZoneId: privateDnsZoneIds.cosmosSql
        }
      }
    ]
  }
}

resource storageDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoints[3]
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'storage-blob'
        properties: {
          privateDnsZoneId: privateDnsZoneIds.storageBlob
        }
      }
    ]
  }
}

#disable-next-line BCP053
var rawWorkspaceId = project.properties.internalId

output accountId string = account.id
output accountName string = account.name
output accountEndpoint string = account.properties.endpoint
output projectId string = project.id
output projectName string = project.name
output projectPrincipalId string = project.identity.principalId
output projectWorkspaceId string = '${substring(rawWorkspaceId, 0, 8)}-${substring(rawWorkspaceId, 8, 4)}-${substring(rawWorkspaceId, 12, 4)}-${substring(rawWorkspaceId, 16, 4)}-${substring(rawWorkspaceId, 20, 12)}'
#disable-next-line no-hardcoded-env-urls
output projectEndpoint string = 'https://${account.name}.services.ai.azure.com/api/projects/${project.name}'
output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output cosmosDbAccountId string = cosmosDbAccount.id
output cosmosDbAccountName string = cosmosDbAccount.name
output searchServiceId string = searchService.id
output searchServiceName string = searchService.name
output cosmosDbConnectionName string = project::cosmosDbConnection.name
output storageConnectionName string = project::storageConnection.name
output searchConnectionName string = project::searchConnection.name
