targetScope = 'resourceGroup'

@description('Azure region for Container Apps resources.')
param location string

@description('Name of the internal Container Apps environment.')
param environmentName string

@description('Dedicated MCP subnet ID.')
param mcpSubnetId string

@description('Log Analytics workspace name.')
param logAnalyticsWorkspaceName string

@description('Tags applied to Container Apps resources.')
param tags object

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource environment 'Microsoft.App/managedEnvironments@2025-01-01' = {
  name: environmentName
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
    vnetConfiguration: {
      infrastructureSubnetId: mcpSubnetId
      internal: true
    }
    zoneRedundant: false
  }
}

output environmentId string = environment.id
output environmentDefaultDomain string = environment.properties.defaultDomain
output environmentStaticIp string = environment.properties.staticIp
