targetScope = 'resourceGroup'

@description('Azure region for monitoring resources.')
param location string

@description('Log Analytics workspace name.')
param logAnalyticsWorkspaceName string

@description('Application Insights component name.')
param applicationInsightsName string

@description('Azure Monitor Private Link Scope name.')
param privateLinkScopeName string

@description('Subnet ID used for the Azure Monitor private endpoint.')
param privateEndpointSubnetId string

@description('Private DNS zone IDs created by the networking module.')
param privateDnsZoneIds object

@description('Tags applied to monitoring resources.')
param tags object

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
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
    DisableIpMasking: false
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
  }
}

resource privateLinkScope 'Microsoft.Insights/privateLinkScopes@2021-09-01' = {
  name: privateLinkScopeName
  location: 'global'
  tags: tags
  properties: {
    accessModeSettings: {
      ingestionAccessMode: 'PrivateOnly'
      queryAccessMode: 'PrivateOnly'
    }
  }
}

resource scopedResources 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-09-01' = [for item in [
  {
    name: 'application-insights'
    resourceId: applicationInsights.id
  }
  {
    name: 'log-analytics'
    resourceId: workspace.id
  }
]: {
  parent: privateLinkScope
  name: item.name
  properties: {
    linkedResourceId: item.resourceId
  }
}]

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${privateLinkScopeName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'azure-monitor'
        properties: {
          privateLinkServiceId: privateLinkScope.id
          groupIds: [
            'azuremonitor'
          ]
        }
      }
    ]
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'azure-monitor'
        properties: {
          privateDnsZoneId: privateDnsZoneIds.azureMonitor
        }
      }
      {
        name: 'log-analytics-oms'
        properties: {
          privateDnsZoneId: privateDnsZoneIds.logAnalyticsOms
        }
      }
      {
        name: 'log-analytics-ods'
        properties: {
          privateDnsZoneId: privateDnsZoneIds.logAnalyticsOds
        }
      }
      {
        name: 'automation-agent'
        properties: {
          privateDnsZoneId: privateDnsZoneIds.automationAgent
        }
      }
      {
        name: 'monitor-storage'
        properties: {
          privateDnsZoneId: privateDnsZoneIds.storageBlob
        }
      }
    ]
  }
}

output logAnalyticsWorkspaceId string = workspace.id
output logAnalyticsWorkspaceName string = workspace.name
output applicationInsightsId string = applicationInsights.id
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
