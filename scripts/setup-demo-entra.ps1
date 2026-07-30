[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectPrincipalId,
    [string]$ApplicationDisplayName = 'foundry-sql-mcp-demo-api'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$tenantId = '16b3c013-d300-468d-ac64-7eda0820b6d3'
$account = az account show --query '{tenant:tenantId}' -o json | ConvertFrom-Json
if ($account.tenant -ne $tenantId) {
    throw "Azure CLI must target tenant $tenantId."
}

$applications = @(az ad app list --display-name $ApplicationDisplayName -o json | ConvertFrom-Json)
if ($applications.Count -gt 1) {
    throw "Multiple Entra applications named '$ApplicationDisplayName' exist."
}

if ($applications.Count -eq 0) {
    $application = az ad app create --display-name $ApplicationDisplayName --sign-in-audience AzureADMyOrg -o json | ConvertFrom-Json
} else {
    $application = $applications[0]
}

$applicationId = $application.appId
$applicationObjectId = $application.id
$audience = "api://$applicationId"
$issuer = "https://login.microsoftonline.com/$tenantId/v2.0"

$existingAppRoles = if ($application.PSObject.Properties['appRoles']) { @($application.appRoles) } else { @() }
$existingRole = @($existingAppRoles | Where-Object { $_.value -eq 'Mcp.Invoke' }) | Select-Object -First 1
if ($existingRole) {
    $appRoleId = $existingRole.id
} else {
    $appRoleId = [guid]::NewGuid().ToString()
}

$appRoles = @(
    @($existingAppRoles | Where-Object { $_.value -ne 'Mcp.Invoke' })
    [pscustomobject]@{
        allowedMemberTypes = @('Application')
        description = 'Invoke the read-only SQL MCP demo server.'
        displayName = 'Invoke SQL MCP'
        id = $appRoleId
        isEnabled = $true
        value = 'Mcp.Invoke'
    }
)

$patchBody = @{
    identifierUris = @($audience)
    appRoles = $appRoles
} | ConvertTo-Json -Depth 20
$patchPath = Join-Path $env:TEMP 'foundry-sql-mcp-demo-app-patch.json'
Set-Content -LiteralPath $patchPath -Value $patchBody -Encoding utf8NoBOM

az rest --method patch --url "https://graph.microsoft.com/v1.0/applications/$applicationObjectId" --headers 'Content-Type=application/json' --body "@$patchPath" | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to configure the MCP Entra application.'
}

$resourceServicePrincipal = az ad sp show --id $applicationId -o json 2>$null | ConvertFrom-Json
if (-not $resourceServicePrincipal) {
    $resourceServicePrincipal = az ad sp create --id $applicationId -o json | ConvertFrom-Json
}

if (-not $resourceServicePrincipal.appRoleAssignmentRequired) {
    $servicePrincipalPatchPath = Join-Path $env:TEMP 'foundry-sql-mcp-demo-sp-patch.json'
    Set-Content -LiteralPath $servicePrincipalPatchPath -Value '{"appRoleAssignmentRequired":true}' -Encoding utf8NoBOM
    az rest --method patch --url "https://graph.microsoft.com/v1.0/servicePrincipals/$($resourceServicePrincipal.id)" --headers 'Content-Type=application/json' --body "@$servicePrincipalPatchPath" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to require MCP app-role assignments.'
    }
}

$existingAssignments = @(az rest --method get --url "https://graph.microsoft.com/v1.0/servicePrincipals/$ProjectPrincipalId/appRoleAssignments" --query 'value' -o json | ConvertFrom-Json)
$assignment = $existingAssignments | Where-Object { $_.resourceId -eq $resourceServicePrincipal.id -and $_.appRoleId -eq $appRoleId }
if (-not $assignment) {
    $assignmentBody = @{
        principalId = $ProjectPrincipalId
        resourceId = $resourceServicePrincipal.id
        appRoleId = $appRoleId
    } | ConvertTo-Json
    $assignmentPath = Join-Path $env:TEMP 'foundry-sql-mcp-demo-role-assignment.json'
    Set-Content -LiteralPath $assignmentPath -Value $assignmentBody -Encoding utf8NoBOM
    az rest --method post --url "https://graph.microsoft.com/v1.0/servicePrincipals/$ProjectPrincipalId/appRoleAssignments" --headers 'Content-Type=application/json' --body "@$assignmentPath" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to assign Mcp.Invoke to the Foundry project identity.'
    }
}

azd env set MCP_AUTH_APP_ID $applicationId
azd env set MCP_AUTH_AUDIENCE $audience
azd env set MCP_AUTH_ISSUER $issuer

[pscustomobject]@{
    ApplicationId = $applicationId
    ApplicationObjectId = $applicationObjectId
    Audience = $audience
    Issuer = $issuer
    AppRoleId = $appRoleId
    ProjectPrincipalId = $ProjectPrincipalId
} | Format-List