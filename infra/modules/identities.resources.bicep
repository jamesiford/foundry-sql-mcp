targetScope = 'resourceGroup'

@description('Azure region for managed identities.')
param location string

@description('Name of the SQL MCP runtime identity.')
param mcpIdentityName string

@description('Tags applied to managed identities.')
param tags object

resource mcpIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: mcpIdentityName
  location: location
  tags: tags
}

output mcpIdentityId string = mcpIdentity.id
output mcpIdentityClientId string = mcpIdentity.properties.clientId
output mcpIdentityPrincipalId string = mcpIdentity.properties.principalId
