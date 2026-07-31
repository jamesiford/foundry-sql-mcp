[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
foreach ($commandName in @('az', 'azd', 'git', 'python')) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "Required command '$commandName' was not found on PATH."
    }
}

$currentValues = azd env get-values --output json | ConvertFrom-Json
$environmentName = if ($env:AZURE_ENV_NAME) {
    $env:AZURE_ENV_NAME
} elseif ($currentValues.PSObject.Properties['AZURE_ENV_NAME']) {
    $currentValues.AZURE_ENV_NAME
} else {
    'foundry-sql-mcp-demo'
}
$location = if ($currentValues.PSObject.Properties['AZURE_LOCATION'] -and $currentValues.AZURE_LOCATION) {
    $currentValues.AZURE_LOCATION
} else {
    'eastus2'
}
$sqlLocation = if ($currentValues.PSObject.Properties['AZURE_SQL_LOCATION'] -and $currentValues.AZURE_SQL_LOCATION) {
    $currentValues.AZURE_SQL_LOCATION
} else {
    'centralus'
}
$expirationDate = if ($currentValues.PSObject.Properties['DEMO_EXPIRATION_DATE'] -and $currentValues.DEMO_EXPIRATION_DATE) {
    $currentValues.DEMO_EXPIRATION_DATE
} else {
    (Get-Date).ToUniversalTime().Date.AddDays(14).ToString('yyyy-MM-dd')
}

& (Join-Path $PSScriptRoot 'setup-demo-environment.ps1') `
    -EnvironmentName $environmentName `
    -Location $location `
    -SqlLocation $sqlLocation `
    -ExpirationDate $expirationDate | Out-Null

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw 'The .NET SDK is required to install Data API builder 2.0.9.'
}
$dabVersion = if (Get-Command dab -ErrorAction SilentlyContinue) { (& dab --version 2>&1 | Out-String) } else { '' }
if ($dabVersion -notmatch '2\.0\.9') {
    $installedTools = dotnet tool list --global | Out-String
    if ($installedTools -match '(?im)^microsoft\.dataapibuilder\s+') {
        dotnet tool update --global Microsoft.DataApiBuilder --version 2.0.9
    } else {
        dotnet tool install --global Microsoft.DataApiBuilder --version 2.0.9
    }
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to install Data API builder 2.0.9.'
    }
}

$modernSqlcmd = 'C:\Program Files\SqlCmd\sqlcmd.exe'
if (-not (Test-Path $modernSqlcmd)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'Modern sqlcmd is missing and winget is unavailable. Install package Microsoft.Sqlcmd.'
    }
    winget install --id Microsoft.Sqlcmd --exact --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $modernSqlcmd)) {
        throw 'Failed to install modern sqlcmd.'
    }
}

$python = Join-Path $repoRoot '.venv/Scripts/python.exe'
if (-not (Test-Path $python)) {
    python -m venv (Join-Path $repoRoot '.venv')
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to create the workspace Python virtual environment.'
    }
}
& $python -m pip install --quiet --disable-pip-version-check -r (Join-Path $repoRoot 'src/agent/requirements.txt')
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to restore prompt-agent Python dependencies.'
}

& (Join-Path $PSScriptRoot 'test-demo.ps1')
if ($LASTEXITCODE -ne 0) {
    throw 'Pre-deployment demo validation failed.'
}

Write-Host "Demo preup completed for environment '$environmentName' (app: $location, SQL: $sqlLocation, expires: $expirationDate)."