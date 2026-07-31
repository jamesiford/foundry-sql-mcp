[CmdletBinding()]
param(
    [string]$EnvironmentName = 'foundry-sql-mcp-demo',
    [int]$LookbackHours = 2,
    [switch]$Provision
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

azd env select $EnvironmentName
$values = azd env get-values --output json | ConvertFrom-Json
$workspaceName = az monitor log-analytics workspace list `
    --subscription $values.AZURE_SUBSCRIPTION_ID `
    --resource-group $values.AZURE_RESOURCE_GROUP `
    --query '[0].name' -o tsv
$workspaceId = az monitor log-analytics workspace show `
    --subscription $values.AZURE_SUBSCRIPTION_ID `
    --resource-group $values.AZURE_RESOURCE_GROUP `
    --workspace-name $workspaceName `
    --query customerId -o tsv

$query = "NSPAccessLogs | where TimeGenerated > ago(${LookbackHours}h) | where Category == 'NspPublicInboundPerimeterRulesDenied' and SourceProtocol == 'TDS:TCP' | distinct SourceIpAddress"
$deniedIps = @(az monitor log-analytics query --workspace $workspaceId --analytics-query $query --query '[].SourceIpAddress' -o tsv) | Where-Object { $_ }
$existingIps = if ($values.PSObject.Properties['DEMO_ADDITIONAL_CLIENT_IPS']) {
    @($values.DEMO_ADDITIONAL_CLIENT_IPS -split ',') | Where-Object { $_ }
} else {
    @()
}
$primaryIps = @($values.DEMO_CLIENT_IP, $values.DEMO_AZURE_CLIENT_IP) | Where-Object { $_ }
$additionalIps = @($existingIps + $deniedIps | Where-Object { $_ -notin $primaryIps } | Sort-Object -Unique)

if ($additionalIps.Count -eq 0) {
    Write-Host 'No additional denied TDS source IPs were found.'
    return
}

$csv = $additionalIps -join ','
azd env set DEMO_ADDITIONAL_CLIENT_IPS $csv
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to store additional demo SQL client IPs.'
}

Write-Host "Stored additional demo SQL client IPs: $csv"
if ($Provision) {
    azd provision --no-prompt
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to provision the updated SQL NSP client rules.'
    }
}