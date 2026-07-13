targetScope = 'subscription'

@description('Azure region for network resources.')
param location string

@description('Resource group that owns the network resources.')
param resourceGroupName string

@description('Virtual network name.')
param virtualNetworkName string

@description('Virtual network address space.')
param virtualNetworkAddressPrefix string = '10.50.0.0/16'

@description('Dedicated subnet for Foundry Agent Service network injection.')
param agentSubnetPrefix string = '10.50.0.0/24'

@description('Dedicated subnet for the internal Container Apps MCP environment.')
param mcpSubnetPrefix string = '10.50.1.0/24'

@description('Subnet for private endpoints.')
param privateEndpointSubnetPrefix string = '10.50.2.0/24'

@description('Dedicated subnet for Azure SQL Managed Instance.')
param sqlManagedInstanceSubnetPrefix string = '10.50.3.0/26'

@description('Tags applied to network resources.')
param tags object = {}

module resources 'networking.resources.bicep' = {
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    virtualNetworkName: virtualNetworkName
    virtualNetworkAddressPrefix: virtualNetworkAddressPrefix
    agentSubnetPrefix: agentSubnetPrefix
    mcpSubnetPrefix: mcpSubnetPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    sqlManagedInstanceSubnetPrefix: sqlManagedInstanceSubnetPrefix
    tags: tags
  }
}

output virtualNetworkId string = resources.outputs.virtualNetworkId
output virtualNetworkName string = resources.outputs.virtualNetworkName
output agentSubnetId string = resources.outputs.agentSubnetId
output mcpSubnetId string = resources.outputs.mcpSubnetId
output privateEndpointSubnetId string = resources.outputs.privateEndpointSubnetId
output sqlManagedInstanceSubnetId string = resources.outputs.sqlManagedInstanceSubnetId
output privateDnsZoneIds object = resources.outputs.privateDnsZoneIds
