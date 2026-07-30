targetScope = 'subscription'

metadata description = 'Public non-production SQL MCP demonstration infrastructure.'

@description('azd environment name.')
param environmentName string = 'foundry-sql-mcp-demo'

@description('Azure region for disposable demo resources.')
param location string

@description('Azure region for the disposable demo SQL Database.')
param sqlLocation string = location

@description('Object ID of the human deployment principal.')
param deployerPrincipalId string

@description('Microsoft Entra user principal name used as Azure SQL administrator.')
param deployerPrincipalName string

@description('Microsoft Entra tenant ID.')
param tenantId string

@description('Optional public client IP allowed to deploy the demo SQL schema.')
param developerClientIp string = ''

@description('Optional Azure control-plane source IP used by corporate traffic routing.')
param developerAzureClientIp string = ''

@description('Demo resource group name.')
param resourceGroupName string = 'rg-${environmentName}'

@description('Chat model deployment name.')
param modelDeploymentName string = 'gpt-5.4-mini'

@description('Chat model catalog name.')
param modelName string = 'gpt-5.4-mini'

@description('Chat model version.')
param modelVersion string = '2026-03-17'

@description('Chat model deployment SKU.')
param modelSkuName string = 'GlobalStandard'

@minValue(1)
@description('Chat model deployment capacity.')
param modelCapacity int = 10

@description('ISO date after which the disposable demo resources should be removed.')
param expirationDate string

@description('Fully qualified ACR image for SQL MCP Server. Empty during bootstrap provisioning.')
param mcpContainerImage string = ''

@description('Entra Application ID URI expected by SQL MCP Server.')
param mcpAuthAudience string = ''

@description('Synthetic SQL database name.')
param sqlDatabaseName string = 'TransferDemo'

var uniqueSuffix = substring(uniqueString(subscription().id, environmentName), 0, 6)
var tags = {
  application: 'foundry-sql-mcp'
  environment: environmentName
  managedBy: 'azd-bicep'
  purpose: 'public-evaluation'
  dataClassification: 'synthetic'
  expirationDate: expirationDate
}

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module resources 'modules/resources.bicep' = {
  scope: resourceGroup
  params: {
    location: location
    sqlLocation: sqlLocation
    deployerPrincipalId: deployerPrincipalId
    deployerPrincipalName: deployerPrincipalName
    tenantId: tenantId
    developerClientIp: developerClientIp
    developerAzureClientIp: developerAzureClientIp
    accountName: 'fdrysqlmcpdemo${uniqueSuffix}'
    projectName: 'project-${environmentName}'
    modelDeploymentName: modelDeploymentName
    modelName: modelName
    modelVersion: modelVersion
    modelSkuName: modelSkuName
    modelCapacity: modelCapacity
    containerRegistryName: 'acrsqlmcpdemo${uniqueSuffix}'
    containerAppsEnvironmentName: 'cae-sql-mcp-demo-${uniqueSuffix}'
    mcpIdentityName: 'id-mcp-${environmentName}'
    sqlServerName: 'sqlsqlmcpdemo${substring(uniqueString(subscription().id, environmentName, sqlLocation), 0, 6)}'
    sqlDatabaseName: sqlDatabaseName
    sqlNetworkSecurityPerimeterName: 'nsp-sql-mcp-demo-${uniqueSuffix}'
    logAnalyticsWorkspaceName: 'law-sql-mcp-demo-${uniqueSuffix}'
    applicationInsightsName: 'appi-sql-mcp-demo-${uniqueSuffix}'
    mcpContainerAppName: 'app-sql-mcp-demo-${uniqueSuffix}'
    mcpContainerImage: mcpContainerImage
    mcpAuthAudience: mcpAuthAudience
    tags: tags
  }
}

output AZURE_RESOURCE_GROUP string = resourceGroup.name
output AZURE_AI_ACCOUNT_NAME string = resources.outputs.accountName
output AZURE_AI_PROJECT_NAME string = resources.outputs.projectName
output AZURE_AI_PROJECT_ID string = resources.outputs.projectId
output AZURE_AI_PROJECT_ENDPOINT string = resources.outputs.projectEndpoint
output AZURE_AI_PROJECT_PRINCIPAL_ID string = resources.outputs.projectPrincipalId
output AZURE_AI_MODEL_DEPLOYMENT_NAME string = modelDeploymentName
output AZURE_CONTAINER_REGISTRY_NAME string = resources.outputs.containerRegistryName
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = resources.outputs.containerRegistryEndpoint
output AZURE_CONTAINER_APPS_ENVIRONMENT_NAME string = resources.outputs.containerAppsEnvironmentName
output AZURE_MCP_IDENTITY_CLIENT_ID string = resources.outputs.mcpIdentityClientId
output AZURE_MCP_IDENTITY_PRINCIPAL_ID string = resources.outputs.mcpIdentityPrincipalId
output AZURE_MCP_IDENTITY_NAME string = 'id-mcp-${environmentName}'
output AZURE_SQL_SERVER_NAME string = resources.outputs.sqlServerName
output AZURE_SQL_SERVER_FQDN string = resources.outputs.sqlServerFqdn
output AZURE_SQL_DATABASE_NAME string = resources.outputs.sqlDatabaseName
output MCP_ENDPOINT string = resources.outputs.mcpEndpoint
output MCP_PROJECT_CONNECTION_NAME string = resources.outputs.mcpConnectionName
output APPLICATIONINSIGHTS_CONNECTION_STRING string = resources.outputs.applicationInsightsConnectionString
