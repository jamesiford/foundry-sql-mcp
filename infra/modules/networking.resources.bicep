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

@description('Paired Azure region used by SQL Managed Instance for storage service dependencies.')
param sqlManagedInstanceSecondaryStorageLocation string = 'eastus2'

@description('Tags applied to network resources.')
param tags object

var agentSubnetName = 'snet-foundry-agent'
var mcpSubnetName = 'snet-mcp'
var privateEndpointSubnetName = 'snet-private-endpoints'
var sqlManagedInstanceSubnetName = 'snet-sqlmi'
var sqlManagedInstanceSubnetSlug = replace(replace(sqlManagedInstanceSubnetPrefix, '.', '-'), '/', '-')
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
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-healthprobe-in-${sqlManagedInstanceSubnetSlug}-v11'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: sqlManagedInstanceSubnetPrefix
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-internal-in-${sqlManagedInstanceSubnetSlug}-v11'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: sqlManagedInstanceSubnetPrefix
          destinationAddressPrefix: sqlManagedInstanceSubnetPrefix
          access: 'Allow'
          priority: 101
          direction: 'Inbound'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-optional-azure-out-${sqlManagedInstanceSubnetSlug}'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: sqlManagedInstanceSubnetPrefix
          destinationAddressPrefix: 'AzureCloud'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-aad-out-${sqlManagedInstanceSubnetSlug}-v11'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: sqlManagedInstanceSubnetPrefix
          destinationAddressPrefix: 'AzureActiveDirectory'
          access: 'Allow'
          priority: 101
          direction: 'Outbound'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-onedsc-out-${sqlManagedInstanceSubnetSlug}-v11'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: sqlManagedInstanceSubnetPrefix
          destinationAddressPrefix: 'OneDsCollector'
          access: 'Allow'
          priority: 102
          direction: 'Outbound'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-internal-out-${sqlManagedInstanceSubnetSlug}-v11'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: sqlManagedInstanceSubnetPrefix
          destinationAddressPrefix: sqlManagedInstanceSubnetPrefix
          access: 'Allow'
          priority: 103
          direction: 'Outbound'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-strg-p-out-${sqlManagedInstanceSubnetSlug}-v11'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: sqlManagedInstanceSubnetPrefix
          destinationAddressPrefix: 'Storage.${location}'
          access: 'Allow'
          priority: 104
          direction: 'Outbound'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-strg-s-out-${sqlManagedInstanceSubnetSlug}-v11'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: sqlManagedInstanceSubnetPrefix
          destinationAddressPrefix: 'Storage.${sqlManagedInstanceSecondaryStorageLocation}'
          access: 'Allow'
          priority: 105
          direction: 'Outbound'
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
    routes: [
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_subnet-${sqlManagedInstanceSubnetSlug}-to-vnetlocal'
        properties: {
          addressPrefix: sqlManagedInstanceSubnetPrefix
          nextHopType: 'VnetLocal'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-AzureActiveDirectory'
        properties: {
          addressPrefix: 'AzureActiveDirectory'
          nextHopType: 'Internet'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-OneDsCollector'
        properties: {
          addressPrefix: 'OneDsCollector'
          nextHopType: 'Internet'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-Storage.${location}'
        properties: {
          addressPrefix: 'Storage.${location}'
          nextHopType: 'Internet'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_mi-Storage.${sqlManagedInstanceSecondaryStorageLocation}'
        properties: {
          addressPrefix: 'Storage.${sqlManagedInstanceSecondaryStorageLocation}'
          nextHopType: 'Internet'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_optional-AzureCloud.${location}'
        properties: {
          addressPrefix: 'AzureCloud.${location}'
          nextHopType: 'Internet'
        }
      }
      {
        name: 'Microsoft.Sql-managedInstances_UseOnly_optional-AzureCloud.${sqlManagedInstanceSecondaryStorageLocation}'
        properties: {
          addressPrefix: 'AzureCloud.${sqlManagedInstanceSecondaryStorageLocation}'
          nextHopType: 'Internet'
        }
      }
    ]
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
