targetScope = 'resourceGroup'

param location string
param sqlLocation string
param deployerPrincipalId string
param deployerPrincipalName string
param tenantId string
param developerClientIp string
param developerAzureClientIp string
param accountName string
param projectName string
param modelDeploymentName string
param modelName string
param modelVersion string
param modelSkuName string
param modelCapacity int
param containerRegistryName string
param containerAppsEnvironmentName string
param mcpIdentityName string
param sqlServerName string
param sqlDatabaseName string
param sqlNetworkSecurityPerimeterName string
param logAnalyticsWorkspaceName string
param applicationInsightsName string
param mcpContainerAppName string
param mcpContainerImage string
param mcpAuthAudience string
param tags object

var foundryUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '53ca6127-db72-4b80-b1b0-d745d6d5456d')
var acrPullRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
var deployMcpApp = !empty(mcpContainerImage)
var databaseConnectionString = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${sqlDatabase.name};Authentication=Active Directory Managed Identity;User Id=${mcpIdentity.properties.clientId};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
var mcpFqdn = mcpApp.?properties.configuration.ingress.fqdn ?? ''

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource mcpIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: mcpIdentityName
  location: location
  tags: tags
}

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: sqlLocation
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: deployerPrincipalName
      principalType: 'User'
      sid: deployerPrincipalId
      tenantId: tenantId
    }
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'SecuredByPerimeter'
    version: '12.0'
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: sqlLocation
  tags: tags
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: {
    maxSizeBytes: 2147483648
  }
}

module sqlNetworkSecurityPerimeter 'br/public:avm/res/network/network-security-perimeter:0.1.4' = {
  name: 'sql-network-security-perimeter'
  params: {
    name: sqlNetworkSecurityPerimeterName
    location: sqlLocation
    enableTelemetry: false
    diagnosticSettings: [
      {
        name: 'nsp-access-logs'
        workspaceResourceId: workspace.id
        logCategoriesAndGroups: [
          {
            categoryGroup: 'allLogs'
          }
        ]
      }
    ]
    profiles: [
      {
        name: 'sql-mcp-demo'
        accessRules: [
          {
            name: 'allow-demo-clients'
            direction: 'Inbound'
            addressPrefixes: concat(
              empty(developerClientIp) ? [] : [
                '${developerClientIp}/32'
              ],
              empty(developerAzureClientIp) || developerAzureClientIp == developerClientIp ? [] : [
                '${developerAzureClientIp}/32'
              ]
            )
          }
          {
            name: 'allow-demo-subscription'
            direction: 'Inbound'
            subscriptions: [
              {
                id: subscription().id
              }
            ]
          }
        ]
      }
    ]
    resourceAssociations: [
      {
        name: 'sql-demo-server'
        profile: 'sql-mcp-demo'
        privateLinkResource: sqlServer.id
        accessMode: 'Enforced'
      }
    ]
    tags: tags
  }
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

resource acrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: registry
  name: guid(mcpIdentity.id, acrPullRoleId, registry.id)
  properties: {
    principalId: mcpIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRoleId
  }
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2025-01-01' = {
  name: containerAppsEnvironmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspace.properties.customerId
        sharedKey: workspace.listKeys().primarySharedKey
      }
    }
    zoneRedundant: false
  }
}

resource mcpApp 'Microsoft.App/containerApps@2025-01-01' = if (deployMcpApp) {
  name: mcpContainerAppName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${mcpIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        allowInsecure: false
        targetPort: 5000
        transport: 'http'
      }
      registries: [
        {
          server: registry.properties.loginServer
          identity: mcpIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'sql-mcp'
          image: mcpContainerImage
          env: [
            {
              name: 'DATABASE_CONNECTION_STRING'
              value: databaseConnectionString
            }
            {
              name: 'DAB_ENVIRONMENT'
              value: 'Production'
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
  dependsOn: [
    acrPullAssignment
  ]
}

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
    publicNetworkAccess: 'Enabled'
  }
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: account
  name: modelDeploymentName
  sku: {
    name: modelSkuName
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
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
    description: 'Public non-production SQL MCP demonstration project.'
    displayName: 'Foundry SQL MCP Public Demo'
  }
}

resource appInsightsConnection 'Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview' = {
  parent: account
  name: '${account.name}-appinsights'
  properties: {
    authType: 'ApiKey'
    category: 'AppInsights'
    credentials: {
      key: applicationInsights.properties.ConnectionString
    }
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: applicationInsights.id
    }
    target: applicationInsights.id
  }
}

resource mcpConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = if (deployMcpApp) {
  parent: project
  name: 'sql-mcp-demo'
  properties: {
    #disable-next-line BCP036
    authType: 'ProjectManagedIdentity'
    category: 'RemoteTool'
    target: 'https://${mcpFqdn}/mcp'
    isSharedToAll: true
    useWorkspaceManagedIdentity: true
    audience: mcpAuthAudience
    metadata: {
      ApiType: 'Azure'
    }
  }
}

resource deployerFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: project
  name: guid(deployerPrincipalId, foundryUserRoleId, project.id)
  properties: {
    principalId: deployerPrincipalId
    principalType: 'User'
    roleDefinitionId: foundryUserRoleId
  }
}

resource projectIdentityFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: account
  name: guid(project.id, foundryUserRoleId, account.id)
  properties: {
    principalId: project.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: foundryUserRoleId
  }
}

output accountName string = account.name
output projectName string = project.name
output projectId string = project.id
output projectEndpoint string = 'https://${account.name}.services.ai.azure.com/api/projects/${project.name}'
output projectPrincipalId string = project.identity.principalId
output containerRegistryName string = registry.name
output containerRegistryEndpoint string = registry.properties.loginServer
output containerAppsEnvironmentName string = containerAppsEnvironment.name
output mcpIdentityClientId string = mcpIdentity.properties.clientId
output mcpIdentityPrincipalId string = mcpIdentity.properties.principalId
output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabaseName string = sqlDatabase.name
output mcpEndpoint string = empty(mcpFqdn) ? '' : 'https://${mcpFqdn}/mcp'
output mcpConnectionName string = deployMcpApp ? mcpConnection.name : ''
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
