targetScope = 'resourceGroup'

@description('Azure region for Azure SQL Managed Instance.')
param location string

@description('Azure SQL Managed Instance name.')
param managedInstanceName string

@description('Dedicated SQL MI subnet ID.')
param subnetId string

@description('Microsoft Entra administrator display name.')
param entraAdministratorLogin string

@description('Microsoft Entra administrator object ID.')
param entraAdministratorObjectId string

@description('Microsoft Entra tenant ID.')
param tenantId string

@description('Microsoft Entra administrator principal type.')
param entraAdministratorPrincipalType string

@description('SQL MI vCore count.')
param vCores int

@description('SQL MI storage size in GB.')
param storageSizeInGB int

@description('SQL MI license type.')
param licenseType string

@description('Tags applied to Azure SQL Managed Instance.')
param tags object

resource managedInstance 'Microsoft.Sql/managedInstances@2024-05-01-preview' = {
  name: managedInstanceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'GP_Gen5'
    tier: 'GeneralPurpose'
    family: 'Gen5'
  }
  properties: {
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: entraAdministratorLogin
      principalType: entraAdministratorPrincipalType
      sid: entraAdministratorObjectId
      tenantId: tenantId
    }
    licenseType: licenseType
    managedInstanceCreateMode: 'Default'
    minimalTlsVersion: '1.2'
    proxyOverride: 'Proxy'
    publicDataEndpointEnabled: false
    storageSizeInGB: storageSizeInGB
    subnetId: subnetId
    timezoneId: 'UTC'
    vCores: vCores
  }
}

output managedInstanceId string = managedInstance.id
output managedInstanceName string = managedInstance.name
output managedInstancePrincipalId string = managedInstance.identity.principalId
output managedInstanceFqdn string = managedInstance.properties.fullyQualifiedDomainName
