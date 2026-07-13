targetScope = 'subscription'

@description('Azure region for Container Apps resources.')
param location string

@description('Resource group that owns Container Apps resources.')
param resourceGroupName string

@description('Name of the internal Container Apps environment.')
param environmentName string

@description('Dedicated MCP subnet ID.')
param mcpSubnetId string

@description('Virtual network ID used for private DNS linking.')
param virtualNetworkId string

@description('Log Analytics workspace name.')
param logAnalyticsWorkspaceName string

@description('Tags applied to Container Apps resources.')
param tags object = {}

module resources 'container-apps.resources.bicep' = {
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    environmentName: environmentName
    mcpSubnetId: mcpSubnetId
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    tags: tags
  }
}

module privateDns 'container-apps.dns.bicep' = {
  scope: resourceGroup(resourceGroupName)
  params: {
    environmentDefaultDomain: resources.outputs.environmentDefaultDomain
    environmentStaticIp: resources.outputs.environmentStaticIp
    virtualNetworkId: virtualNetworkId
    tags: tags
  }
}

output environmentId string = resources.outputs.environmentId
output environmentDefaultDomain string = resources.outputs.environmentDefaultDomain
output environmentStaticIp string = resources.outputs.environmentStaticIp
