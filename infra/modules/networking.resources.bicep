targetScope = 'resourceGroup'

@description('Azure region for network resources.')
param location string

@description('Virtual network name.')
param virtualNetworkName string

@description('Virtual network address space.')
param virtualNetworkAddressPrefix string

@description('Dedicated subnet for Foundry Agent Service network injection.')
param agentSubnetPrefix string

@description('Dedicated subnet for the internal Container Apps MCP environment.')
param mcpSubnetPrefix string

@description('Subnet for private endpoints.')
param privateEndpointSubnetPrefix string

@description('Dedicated subnet for Azure SQL Managed Instance.')
param sqlManagedInstanceSubnetPrefix string

@description('Tags applied to network resources.')
param tags object

var agentSubnetName = 'snet-foundry-agent'
var mcpSubnetName = 'snet-mcp'
var privateEndpointSubnetName = 'snet-private-endpoints'
var sqlManagedInstanceSubnetName = 'snet-sqlmi'
var privateDnsZoneNames = [
  'privatelink.services.ai.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.cognitiveservices.azure.com'
  'privatelink.search.windows.net'
  'privatelink.documents.azure.com'
  'privatelink.blob.${environment().suffixes.storage}'
  'privatelink.monitor.azure.com'
  'privatelink.oms.opinsights.azure.com'
  'privatelink.ods.opinsights.azure.com'
  'privatelink.agentsvc.azure-automation.net'
]

resource sqlManagedInstanceNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${sqlManagedInstanceSubnetName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowMcpTdsInbound'
        properties: {
          description: 'Allow the SQL MCP workload to reach the SQL MI VNet-local proxy endpoint.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: mcpSubnetPrefix
          destinationAddressPrefix: sqlManagedInstanceSubnetPrefix
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource sqlManagedInstanceRouteTable 'Microsoft.Network/routeTables@2024-05-01' = {
  name: 'rt-${sqlManagedInstanceSubnetName}'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
    routes: []
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: virtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkAddressPrefix
      ]
    }
    subnets: [
      {
        name: agentSubnetName
        properties: {
          addressPrefix: agentSubnetPrefix
          delegations: [
            {
              name: 'foundryAgentService'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: mcpSubnetName
        properties: {
          addressPrefix: mcpSubnetPrefix
          delegations: [
            {
              name: 'mcpContainerApps'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: sqlManagedInstanceSubnetName
        properties: {
          addressPrefix: sqlManagedInstanceSubnetPrefix
          networkSecurityGroup: {
            id: sqlManagedInstanceNetworkSecurityGroup.id
          }
          routeTable: {
            id: sqlManagedInstanceRouteTable.id
          }
          delegations: [
            {
              name: 'sqlManagedInstance'
              properties: {
                serviceName: 'Microsoft.Sql/managedInstances'
              }
            }
          ]
        }
      }
    ]
  }
}

resource agentSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: virtualNetwork
  name: agentSubnetName
}

resource mcpSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: virtualNetwork
  name: mcpSubnetName
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: virtualNetwork
  name: privateEndpointSubnetName
}

resource sqlManagedInstanceSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: virtualNetwork
  name: sqlManagedInstanceSubnetName
}

resource privateDnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zoneName in privateDnsZoneNames: {
  name: zoneName
  location: 'global'
  tags: tags
}]

resource privateDnsZoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zoneName, index) in privateDnsZoneNames: {
  parent: privateDnsZones[index]
  name: 'link-${uniqueString(virtualNetwork.id, zoneName)}'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: virtualNetwork.id
    }
    registrationEnabled: false
  }
}]

output virtualNetworkId string = virtualNetwork.id
output virtualNetworkName string = virtualNetwork.name
output agentSubnetId string = agentSubnet.id
output mcpSubnetId string = mcpSubnet.id
output privateEndpointSubnetId string = privateEndpointSubnet.id
output sqlManagedInstanceSubnetId string = sqlManagedInstanceSubnet.id
output privateDnsZoneIds object = {
  foundryServices: privateDnsZones[0].id
  openAi: privateDnsZones[1].id
  cognitiveServices: privateDnsZones[2].id
  search: privateDnsZones[3].id
  cosmosSql: privateDnsZones[4].id
  storageBlob: privateDnsZones[5].id
  azureMonitor: privateDnsZones[6].id
  logAnalyticsOms: privateDnsZones[7].id
  logAnalyticsOds: privateDnsZones[8].id
  automationAgent: privateDnsZones[9].id
}
