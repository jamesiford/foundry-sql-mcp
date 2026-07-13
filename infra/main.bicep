targetScope = 'subscription'

metadata description = 'Phase 2 private infrastructure for the Microsoft Foundry SQL MCP reference architecture.'

@description('azd environment name.')
param environmentName string

@description('Primary Azure region.')
param location string

@description('Resource group name.')
param resourceGroupName string = 'rg-${environmentName}'

@description('Microsoft Entra administrator display name for SQL MI.')
param sqlAdministratorLogin string

@description('Microsoft Entra administrator object ID for SQL MI.')
param sqlAdministratorObjectId string

@description('Microsoft Entra tenant ID.')
param tenantId string

@description('Object ID of the deployment user who needs Foundry project access.')
param deployerPrincipalId string

@description('Microsoft Entra administrator principal type for SQL MI.')
@allowed([
  'User'
  'Group'
  'Application'
])
param sqlAdministratorPrincipalType string = 'User'

@description('Model deployment name.')
param modelDeploymentName string = 'gpt-5.4-mini'

@description('Model catalog name.')
param modelName string = 'gpt-5.4-mini'

@description('Model format.')
param modelFormat string = 'OpenAI'

@description('Model version. Validate availability in the target region before deployment.')
param modelVersion string = '2026-03-17'

@description('Model deployment SKU.')
param modelSkuName string = 'GlobalStandard'

@description('Model deployment capacity.')
@minValue(1)
param modelCapacity int = 10

@description('SQL MI vCore count.')
param sqlManagedInstanceVCores int = 4

@description('SQL MI storage size in GB.')
param sqlManagedInstanceStorageSizeInGB int = 32

@description('SQL MI license type.')
param sqlManagedInstanceLicenseType string = 'LicenseIncluded'

@description('Tags applied to resources.')
param tags object = {
  application: 'foundry-sql-mcp'
  environment: environmentName
  managedBy: 'azd-bicep'
  dataClassification: 'synthetic'
}

var uniqueSuffix = substring(uniqueString(subscription().id, environmentName), 0, 6)
var virtualNetworkName = 'vnet-${environmentName}'
var mcpIdentityName = 'id-mcp-${environmentName}'
var logAnalyticsWorkspaceName = 'law-foundry-sql-mcp-${uniqueSuffix}'
var applicationInsightsName = 'appi-foundry-sql-mcp-${uniqueSuffix}'
var monitorPrivateLinkScopeName = 'ampls-foundry-sql-mcp-${uniqueSuffix}'
var containerAppsEnvironmentName = 'cae-sql-mcp-${uniqueSuffix}'
var foundryAccountName = 'fdrysqlmcp${uniqueSuffix}'
var foundryProjectName = 'project-${environmentName}'
var storageAccountName = 'stsqlmcp${uniqueSuffix}'
var cosmosDbAccountName = 'cosmos-sqlmcp-${uniqueSuffix}'
var searchServiceName = 'srch-sqlmcp-${uniqueSuffix}'
var sqlManagedInstanceName = 'sqlmi-sqlmcp-${uniqueSuffix}'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module networking 'modules/networking.bicep' = {
  params: {
    location: location
    resourceGroupName: resourceGroupName
    virtualNetworkName: virtualNetworkName
    tags: tags
  }
  dependsOn: [
    resourceGroup
  ]
}

module identities 'modules/identities.bicep' = {
  params: {
    location: location
    resourceGroupName: resourceGroupName
    mcpIdentityName: mcpIdentityName
    tags: tags
  }
  dependsOn: [
    resourceGroup
  ]
}

module monitoring 'modules/monitoring.bicep' = {
  params: {
    location: location
    resourceGroupName: resourceGroupName
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    applicationInsightsName: applicationInsightsName
    privateLinkScopeName: monitorPrivateLinkScopeName
    privateEndpointSubnetId: networking.outputs.privateEndpointSubnetId
    privateDnsZoneIds: networking.outputs.privateDnsZoneIds
    tags: tags
  }
}

module sqlMi 'modules/sql-mi.bicep' = {
  params: {
    location: location
    resourceGroupName: resourceGroupName
    managedInstanceName: sqlManagedInstanceName
    subnetId: networking.outputs.sqlManagedInstanceSubnetId
    entraAdministratorLogin: sqlAdministratorLogin
    entraAdministratorObjectId: sqlAdministratorObjectId
    tenantId: tenantId
    entraAdministratorPrincipalType: sqlAdministratorPrincipalType
    vCores: sqlManagedInstanceVCores
    storageSizeInGB: sqlManagedInstanceStorageSizeInGB
    licenseType: sqlManagedInstanceLicenseType
    tags: tags
  }
}

module containerApps 'modules/container-apps.bicep' = {
  params: {
    location: location
    resourceGroupName: resourceGroupName
    environmentName: containerAppsEnvironmentName
    mcpSubnetId: networking.outputs.mcpSubnetId
    virtualNetworkId: networking.outputs.virtualNetworkId
    logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsWorkspaceName
    tags: tags
  }
}

module foundry 'modules/foundry.bicep' = {
  params: {
    location: location
    resourceGroupName: resourceGroupName
    accountName: foundryAccountName
    projectName: foundryProjectName
    projectDisplayName: 'Foundry SQL MCP ${environmentName}'
    projectDescription: 'Private Microsoft Foundry project for comparing SQL MCP and deferred Foundry IQ data paths.'
    storageAccountName: storageAccountName
    cosmosDbAccountName: cosmosDbAccountName
    searchServiceName: searchServiceName
    modelDeploymentName: modelDeploymentName
    modelName: modelName
    modelFormat: modelFormat
    modelVersion: modelVersion
    modelSkuName: modelSkuName
    modelCapacity: modelCapacity
    agentSubnetId: networking.outputs.agentSubnetId
    privateEndpointSubnetId: networking.outputs.privateEndpointSubnetId
    privateDnsZoneIds: networking.outputs.privateDnsZoneIds
    applicationInsightsId: monitoring.outputs.applicationInsightsId
    applicationInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
    tags: tags
  }
}

module roleAssignments 'modules/role-assignments.bicep' = {
  params: {
    resourceGroupName: resourceGroupName
    projectPrincipalId: foundry.outputs.projectPrincipalId
    projectWorkspaceId: foundry.outputs.projectWorkspaceId
    storageAccountName: foundry.outputs.storageAccountName
    cosmosDbAccountName: foundry.outputs.cosmosDbAccountName
    searchServiceName: foundry.outputs.searchServiceName
    foundryAccountName: foundry.outputs.accountName
    foundryProjectName: foundry.outputs.projectName
    deployerPrincipalId: deployerPrincipalId
  }
}

module capabilityHost 'modules/foundry-capability-host.bicep' = {
  params: {
    resourceGroupName: resourceGroupName
    accountName: foundry.outputs.accountName
    projectName: foundry.outputs.projectName
    cosmosDbConnectionName: foundry.outputs.cosmosDbConnectionName
    storageConnectionName: foundry.outputs.storageConnectionName
    searchConnectionName: foundry.outputs.searchConnectionName
  }
  dependsOn: [
    roleAssignments
  ]
}

output AZURE_RESOURCE_GROUP string = resourceGroupName
output AZURE_AI_ACCOUNT_NAME string = foundry.outputs.accountName
output AZURE_AI_PROJECT_NAME string = foundry.outputs.projectName
output AZURE_AI_PROJECT_ENDPOINT string = foundry.outputs.projectEndpoint
output AZURE_AI_MODEL_DEPLOYMENT_NAME string = modelDeploymentName
output AZURE_SQL_MANAGED_INSTANCE_NAME string = sqlMi.outputs.managedInstanceName
output AZURE_SQL_MANAGED_INSTANCE_FQDN string = sqlMi.outputs.managedInstanceFqdn
output AZURE_CONTAINER_APPS_ENVIRONMENT_NAME string = containerAppsEnvironmentName
output AZURE_CONTAINER_APPS_ENVIRONMENT_DOMAIN string = containerApps.outputs.environmentDefaultDomain
output AZURE_MCP_IDENTITY_CLIENT_ID string = identities.outputs.mcpIdentityClientId
output APPLICATIONINSIGHTS_CONNECTION_STRING string = monitoring.outputs.applicationInsightsConnectionString
output FOUNDRY_CAPABILITY_HOST_NAME string = capabilityHost.outputs.capabilityHostName
