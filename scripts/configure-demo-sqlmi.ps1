[CmdletBinding()]
param(
    [string]$SqlResourceGroup = 'rg-foundry-sql-mcp-dev-centralus',
    [string]$SqlManagedInstanceName = 'sqlmi-sqlmcp-d3q5zq',
    [string]$SqlNetworkSecurityGroupName = 'nsg-snet-sqlmi'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$managedInstance = az sql mi show --resource-group $SqlResourceGroup --name $SqlManagedInstanceName -o json | ConvertFrom-Json
if ($managedInstance.state -eq 'Stopped') {
    az sql mi start --resource-group $SqlResourceGroup --managed-instance $SqlManagedInstanceName
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to start SQL MI.'
    }
}

az sql mi update --resource-group $SqlResourceGroup --name $SqlManagedInstanceName --public-data-endpoint-enabled true | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to enable the SQL MI public data endpoint.'
}

az network nsg rule create `
    --resource-group $SqlResourceGroup `
    --nsg-name $SqlNetworkSecurityGroupName `
    --name AllowDemoMcpPublicTds `
    --priority 1090 `
    --direction Inbound `
    --access Allow `
    --protocol Tcp `
    --source-address-prefixes AzureCloud `
    --source-port-ranges '*' `
    --destination-address-prefixes '*' `
    --destination-port-ranges 3342 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to create the SQL MI demo NSG rule.'
}

$privateFqdn = $managedInstance.fullyQualifiedDomainName
$firstDot = $privateFqdn.IndexOf('.')
$publicFqdn = $privateFqdn.Substring(0, $firstDot) + '.public' + $privateFqdn.Substring($firstDot)
azd env set SQL_MI_PUBLIC_FQDN $publicFqdn

[pscustomobject]@{
    PublicFqdn = $publicFqdn
    AllowedSource = 'AzureCloud'
    PublicDataEndpointEnabled = $true
} | Format-List