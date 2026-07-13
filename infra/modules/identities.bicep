targetScope = 'subscription'

@description('Azure region for managed identities.')
param location string

@description('Resource group that owns managed identities.')
param resourceGroupName string

@description('Name of the SQL MCP runtime identity.')
param mcpIdentityName string

@description('Tags applied to managed identities.')
param tags object = {}

module resources 'identities.resources.bicep' = {
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    mcpIdentityName: mcpIdentityName
    tags: tags
  }
}

output mcpIdentityId string = resources.outputs.mcpIdentityId
output mcpIdentityClientId string = resources.outputs.mcpIdentityClientId
output mcpIdentityPrincipalId string = resources.outputs.mcpIdentityPrincipalId
