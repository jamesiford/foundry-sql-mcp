[CmdletBinding()]
param(
    [switch]$ConfirmCleanup,
    [switch]$DropDatabase,
    [string]$EnvironmentName = 'foundry-sql-mcp-demo',
    [string]$SqlResourceGroup = 'rg-foundry-sql-mcp-dev-centralus',
    [string]$SqlManagedInstanceName = 'sqlmi-sqlmcp-d3q5zq',
    [string]$SqlNetworkSecurityGroupName = 'nsg-snet-sqlmi',
    [string]$DatabaseName = 'TransferDemo'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ConfirmCleanup) {
    throw 'Pass -ConfirmCleanup to remove the public demo resources and SQL MI exception.'
}

azd env select $EnvironmentName
$values = azd env get-values --output json | ConvertFrom-Json
$publicFqdn = $values.SQL_MI_PUBLIC_FQDN
$mcpIdentityName = $values.AZURE_MCP_IDENTITY_NAME
$mcpAuthAppId = $values.MCP_AUTH_APP_ID

if (-not [string]::IsNullOrWhiteSpace($publicFqdn) -and (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    if ($DropDatabase) {
        $dropSql = "IF DB_ID(N'$DatabaseName') IS NOT NULL BEGIN ALTER DATABASE [$DatabaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$DatabaseName]; END;"
        & sqlcmd -S "$publicFqdn,3342" -d master -G -b -Q $dropSql
    } elseif (-not [string]::IsNullOrWhiteSpace($mcpIdentityName)) {
        $escapedIdentity = $mcpIdentityName.Replace(']', ']]')
        $removeUserSql = "USE [$DatabaseName]; IF DATABASE_PRINCIPAL_ID(N'$mcpIdentityName') IS NOT NULL BEGIN ALTER ROLE [mcp_reader] DROP MEMBER [$escapedIdentity]; DROP USER [$escapedIdentity]; END;"
        & sqlcmd -S "$publicFqdn,3342" -d master -G -b -Q $removeUserSql
    }
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to clean up the demo SQL principal or database.'
    }
}

az network nsg rule delete --resource-group $SqlResourceGroup --nsg-name $SqlNetworkSecurityGroupName --name AllowDemoMcpPublicTds 2>$null
az sql mi update --resource-group $SqlResourceGroup --name $SqlManagedInstanceName --public-data-endpoint-enabled false | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to disable the SQL MI public data endpoint.'
}

azd down --environment $EnvironmentName --force --purge --no-prompt
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to delete the demo resource group through azd.'
}

if (-not [string]::IsNullOrWhiteSpace($mcpAuthAppId)) {
    az ad app delete --id $mcpAuthAppId
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to delete the demo MCP Entra application.'
    }
}

az sql mi stop --resource-group $SqlResourceGroup --managed-instance $SqlManagedInstanceName
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to stop SQL MI after demo cleanup.'
}

Write-Host 'Public SQL MCP demo cleanup completed.'