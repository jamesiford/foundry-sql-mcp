targetScope = 'subscription'

@description('Azure region for monitoring resources.')
param location string

@description('Resource group that owns monitoring resources.')
param resourceGroupName string

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
param tags object = {}

module resources 'monitoring.resources.bicep' = {
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    applicationInsightsName: applicationInsightsName
    privateLinkScopeName: privateLinkScopeName
    privateEndpointSubnetId: privateEndpointSubnetId
    privateDnsZoneIds: privateDnsZoneIds
    tags: tags
  }
}

output logAnalyticsWorkspaceId string = resources.outputs.logAnalyticsWorkspaceId
output logAnalyticsWorkspaceName string = resources.outputs.logAnalyticsWorkspaceName
output applicationInsightsId string = resources.outputs.applicationInsightsId
output applicationInsightsConnectionString string = resources.outputs.applicationInsightsConnectionString
