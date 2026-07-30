[CmdletBinding()]
param(
    [string]$EnvironmentName = 'foundry-sql-mcp-demo',
    [Parameter(Mandatory)]
    [string]$Location,
    [Parameter(Mandatory)]
    [string]$ExpirationDate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$subscriptionId = '49d5f6b0-70f2-4563-acdc-9a31d2eee119'
$tenantId = '16b3c013-d300-468d-ac64-7eda0820b6d3'
$account = az account show --query '{subscription:id,tenant:tenantId,user:user.name}' -o json | ConvertFrom-Json
if ($account.subscription -ne $subscriptionId -or $account.tenant -ne $tenantId) {
    throw "Azure CLI must target subscription $subscriptionId in tenant $tenantId."
}

$existingEnvironments = azd env list --output json | ConvertFrom-Json
if ($existingEnvironments.Name -contains $EnvironmentName) {
    azd env select $EnvironmentName
} else {
    azd env new $EnvironmentName --no-prompt
}

$deployerObjectId = az ad signed-in-user show --query id -o tsv
$values = [ordered]@{
    AZURE_SUBSCRIPTION_ID = $subscriptionId
    AZURE_TENANT_ID = $tenantId
    AZURE_LOCATION = $Location
    AZURE_DEPLOYER_OBJECT_ID = $deployerObjectId
    AZURE_AI_MODEL_DEPLOYMENT_NAME = 'gpt-5.4-mini'
    AZURE_AI_MODEL_NAME = 'gpt-5.4-mini'
    AZURE_AI_MODEL_VERSION = '2026-03-17'
    AZURE_AI_MODEL_SKU = 'GlobalStandard'
    AZURE_AI_MODEL_CAPACITY = '10'
    DEMO_EXPIRATION_DATE = $ExpirationDate
    SQL_DATABASE_NAME = 'TransferDemo'
}

foreach ($entry in $values.GetEnumerator()) {
    azd env set $entry.Key $entry.Value
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set azd value $($entry.Key)."
    }
}

azd env get-values