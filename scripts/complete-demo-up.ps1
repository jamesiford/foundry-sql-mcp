[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$values = azd env get-values --output json | ConvertFrom-Json
foreach ($name in @(
    'AZURE_AI_PROJECT_PRINCIPAL_ID',
    'AZURE_CONTAINER_REGISTRY_NAME',
    'AZURE_SQL_SERVER_FQDN',
    'AZURE_MCP_IDENTITY_CLIENT_ID'
)) {
    if (-not $values.PSObject.Properties[$name] -or [string]::IsNullOrWhiteSpace($values.$name)) {
        throw "Base provisioning did not produce required azd value $name."
    }
}

& (Join-Path $PSScriptRoot 'setup-demo-entra.ps1') `
    -ProjectPrincipalId $values.AZURE_AI_PROJECT_PRINCIPAL_ID `
    -TenantId $values.AZURE_TENANT_ID `
    -ApplicationDisplayName "$($values.AZURE_ENV_NAME)-api"

$values = azd env get-values --output json | ConvertFrom-Json
& (Join-Path $PSScriptRoot 'build-demo-mcp.ps1') `
    -RegistryName $values.AZURE_CONTAINER_REGISTRY_NAME `
    -McpApplicationId $values.MCP_AUTH_APP_ID `
    -TenantId $values.AZURE_TENANT_ID

& (Join-Path $PSScriptRoot 'deploy-demo-database-with-bootstrap.ps1')

azd provision --no-prompt
if ($LASTEXITCODE -ne 0) {
    throw 'The image-dependent Container App and RemoteTool provisioning pass failed.'
}

& (Join-Path $PSScriptRoot 'register-demo-agent.ps1')
& (Join-Path $PSScriptRoot 'test-demo-agent.ps1')

$values = azd env get-values --output json | ConvertFrom-Json
$appName = az resource list `
    --subscription $values.AZURE_SUBSCRIPTION_ID `
    --resource-group $values.AZURE_RESOURCE_GROUP `
    --resource-type Microsoft.App/containerApps `
    --query '[0].name' -o tsv
$appState = az containerapp show `
    --subscription $values.AZURE_SUBSCRIPTION_ID `
    --resource-group $values.AZURE_RESOURCE_GROUP `
    --name $appName `
    --query properties.runningStatus -o tsv
if ($LASTEXITCODE -ne 0 -or $appState -ne 'Running') {
    throw "SQL MCP Container App is not running (state: $appState)."
}

Write-Host 'azd up completed the public SQL MCP demo end to end.'
Write-Host "Foundry project: $($values.AZURE_AI_PROJECT_NAME)"
Write-Host "MCP endpoint: $($values.MCP_ENDPOINT)"