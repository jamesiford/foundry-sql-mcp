[CmdletBinding()]
param(
    [string]$EnvironmentName = 'foundry-sql-mcp-demo',
    [string]$SubscriptionId,
    [string]$TenantId,
    [Parameter(Mandatory)]
    [string]$Location,
    [string]$SqlLocation = $Location,
    [Parameter(Mandatory)]
    [string]$ExpirationDate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$account = az account show --query '{subscription:id,tenant:tenantId,user:user.name}' -o json | ConvertFrom-Json
$SubscriptionId = if ($SubscriptionId) { $SubscriptionId } else { $account.subscription }
$TenantId = if ($TenantId) { $TenantId } else { $account.tenant }
if ($account.subscription -ne $SubscriptionId -or $account.tenant -ne $TenantId) {
    throw "Azure CLI must target subscription $SubscriptionId in tenant $TenantId."
}

$existingEnvironments = azd env list --output json | ConvertFrom-Json
if ($existingEnvironments.Name -contains $EnvironmentName) {
    azd env select $EnvironmentName
} else {
    azd env new $EnvironmentName --no-prompt
}

$deployerObjectId = az ad signed-in-user show --query id -o tsv
$deployerPrincipalName = az ad signed-in-user show --query userPrincipalName -o tsv
$developerClientIp = (Invoke-RestMethod -Uri 'https://api.ipify.org').Trim()
$managementToken = az account get-access-token --resource 'https://management.azure.com/' --query accessToken -o tsv
$tokenPayload = $managementToken.Split('.')[1].Replace('-', '+').Replace('_', '/')
while ($tokenPayload.Length % 4) {
    $tokenPayload += '='
}
$developerAzureClientIp = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($tokenPayload)) | ConvertFrom-Json).ipaddr
$values = [ordered]@{
    AZURE_SUBSCRIPTION_ID = $SubscriptionId
    AZURE_TENANT_ID = $TenantId
    AZURE_LOCATION = $Location
    AZURE_SQL_LOCATION = $SqlLocation
    AZURE_DEPLOYER_OBJECT_ID = $deployerObjectId
    AZURE_SQL_ADMIN_LOGIN = $deployerPrincipalName
    AZURE_AI_MODEL_DEPLOYMENT_NAME = 'gpt-5.4-mini'
    AZURE_AI_MODEL_NAME = 'gpt-5.4-mini'
    AZURE_AI_MODEL_VERSION = '2026-03-17'
    AZURE_AI_MODEL_SKU = 'GlobalStandard'
    AZURE_AI_MODEL_CAPACITY = '10'
    DEMO_EXPIRATION_DATE = $ExpirationDate
    SQL_DATABASE_NAME = 'TransferDemo'
    DEMO_CLIENT_IP = $developerClientIp
    DEMO_AZURE_CLIENT_IP = $developerAzureClientIp
}

foreach ($entry in $values.GetEnumerator()) {
    azd env set $entry.Key $entry.Value
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set azd value $($entry.Key)."
    }
}

azd env get-values