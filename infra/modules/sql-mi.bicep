targetScope = 'subscription'

@description('Azure region for Azure SQL Managed Instance.')
param location string

@description('Resource group that owns Azure SQL Managed Instance.')
param resourceGroupName string

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
@allowed([
  'User'
  'Group'
  'Application'
])
param entraAdministratorPrincipalType string = 'User'

@description('SQL MI vCore count.')
@allowed([
  4
  8
  16
  24
  32
  40
  64
  80
])
param vCores int = 4

@description('SQL MI storage size in GB.')
@minValue(32)
param storageSizeInGB int = 32

@description('SQL MI license type.')
@allowed([
  'LicenseIncluded'
  'BasePrice'
])
param licenseType string = 'LicenseIncluded'

@description('Tags applied to Azure SQL Managed Instance.')
param tags object = {}

module resources 'sql-mi.resources.bicep' = {
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    managedInstanceName: managedInstanceName
    subnetId: subnetId
    entraAdministratorLogin: entraAdministratorLogin
    entraAdministratorObjectId: entraAdministratorObjectId
    tenantId: tenantId
    entraAdministratorPrincipalType: entraAdministratorPrincipalType
    vCores: vCores
    storageSizeInGB: storageSizeInGB
    licenseType: licenseType
    tags: tags
  }
}

output managedInstanceId string = resources.outputs.managedInstanceId
output managedInstanceName string = resources.outputs.managedInstanceName
output managedInstancePrincipalId string = resources.outputs.managedInstancePrincipalId
output managedInstanceFqdn string = resources.outputs.managedInstanceFqdn
