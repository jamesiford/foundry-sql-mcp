[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-AzRestWithRetry {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('get', 'put')]
        [string]$Method,
        [Parameter(Mandatory)]
        [string]$Url,
        [string]$BodyPath,
        [int]$MaximumAttempts = 6
    )

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        $output = if ($BodyPath) {
            az rest --method $Method --url $Url --body "@$BodyPath" --only-show-errors 2>$null | Out-String
        } else {
            az rest --method $Method --url $Url --only-show-errors 2>$null | Out-String
        }
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($output)) {
            return $output | ConvertFrom-Json
        }
        if ($attempt -lt $MaximumAttempts) {
            Write-Warning "Azure REST $Method attempt $attempt failed; retrying."
            [System.Threading.Tasks.Task]::Delay(5000).GetAwaiter().GetResult()
        }
    }
    throw "Azure REST $Method failed after $MaximumAttempts attempts: $Url"
}

function Wait-EffectiveNspRule {
    param(
        [Parameter(Mandatory)]
        [string]$ConfigurationUrl,
        [Parameter(Mandatory)]
        [string[]]$ExpectedPrefixes,
        [int]$MaximumAttempts = 30
    )

    $expected = @($ExpectedPrefixes | Sort-Object -Unique)
    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        $effectiveOutput = az rest --method get --url $ConfigurationUrl --only-show-errors 2>$null | Out-String
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($effectiveOutput)) {
            $effective = $effectiveOutput | ConvertFrom-Json
            $rule = $effective.value[0].properties.profile.accessRules | Where-Object { $_.name -eq 'allow-demo-clients' }
            $actual = @($rule.properties.addressPrefixes | Sort-Object -Unique)
            if (@(Compare-Object $expected $actual).Count -eq 0) {
                return
            }
        }
        [System.Threading.Tasks.Task]::Delay(5000).GetAwaiter().GetResult()
    }
    throw "SQL did not consume NSP prefixes '$($expected -join ',')' within the expected interval."
}

$values = azd env get-values --output json | ConvertFrom-Json
foreach ($name in @(
    'AZURE_SUBSCRIPTION_ID',
    'AZURE_RESOURCE_GROUP',
    'AZURE_SQL_SERVER_NAME',
    'AZURE_SQL_SERVER_FQDN',
    'AZURE_SQL_DATABASE_NAME',
    'AZURE_MCP_IDENTITY_NAME',
    'AZURE_MCP_IDENTITY_CLIENT_ID'
)) {
    if (-not $values.PSObject.Properties[$name] -or [string]::IsNullOrWhiteSpace($values.$name)) {
        throw "azd value $name is missing after base provisioning."
    }
}

$nspName = az resource list `
    --subscription $values.AZURE_SUBSCRIPTION_ID `
    --resource-group $values.AZURE_RESOURCE_GROUP `
    --resource-type Microsoft.Network/networkSecurityPerimeters `
    --query '[0].name' -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($nspName)) {
    throw 'The demo SQL Network Security Perimeter was not found.'
}

$baseUrl = "https://management.azure.com/subscriptions/$($values.AZURE_SUBSCRIPTION_ID)/resourceGroups/$($values.AZURE_RESOURCE_GROUP)"
$ruleUrl = "$baseUrl/providers/Microsoft.Network/networkSecurityPerimeters/$nspName/profiles/sql-mcp-demo/accessRules/allow-demo-clients?api-version=2024-07-01"
$configurationUrl = "$baseUrl/providers/Microsoft.Sql/servers/$($values.AZURE_SQL_SERVER_NAME)/networkSecurityPerimeterConfigurations?api-version=2023-08-01-preview"
$currentRule = Invoke-AzRestWithRetry -Method get -Url $ruleUrl
$restoreProperties = $currentRule.properties
$restorePrefixes = @($restoreProperties.addressPrefixes)
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "foundry-sql-mcp-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$bootstrapPath = Join-Path $tempRoot 'bootstrap.json'
$restorePath = Join-Path $tempRoot 'restore.json'
@{ properties = @{ direction = 'Inbound'; addressPrefixes = @('0.0.0.0/0') } } |
    ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $bootstrapPath -Encoding utf8NoBOM
@{ properties = $restoreProperties } |
    ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $restorePath -Encoding utf8NoBOM

$migrationError = $null
$restoreError = $null
try {
    Invoke-AzRestWithRetry -Method put -Url $ruleUrl -BodyPath $bootstrapPath | Out-Null
    Wait-EffectiveNspRule -ConfigurationUrl $configurationUrl -ExpectedPrefixes @('0.0.0.0/0')

    & (Join-Path $PSScriptRoot 'deploy-demo-database.ps1') `
        -Server "$($values.AZURE_SQL_SERVER_FQDN),1433" `
        -DatabaseName $values.AZURE_SQL_DATABASE_NAME `
        -McpIdentityName $values.AZURE_MCP_IDENTITY_NAME `
        -McpIdentityClientId $values.AZURE_MCP_IDENTITY_CLIENT_ID
} catch {
    $migrationError = $_
} finally {
    try {
        Invoke-AzRestWithRetry -Method put -Url $ruleUrl -BodyPath $restorePath | Out-Null
        Wait-EffectiveNspRule -ConfigurationUrl $configurationUrl -ExpectedPrefixes $restorePrefixes
    } catch {
        $restoreError = $_
    }
    Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($restoreError) {
    throw $restoreError
}
if ($migrationError) {
    throw $migrationError
}
Write-Host 'Demo SQL migrations completed and the prior NSP client rule was restored.'