[CmdletBinding()]
param(
    [switch]$ConfirmCleanup,
    [string]$EnvironmentName = 'foundry-sql-mcp-demo'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ConfirmCleanup) {
    throw 'Pass -ConfirmCleanup to remove the public demo resources.'
}

azd env select $EnvironmentName
$values = azd env get-values --output json | ConvertFrom-Json
$mcpAuthAppId = $values.MCP_AUTH_APP_ID

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

Write-Host 'Public SQL MCP demo cleanup completed.'