[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Server,

    [Parameter(Mandatory)]
    [string]$McpIdentityName,

    [Parameter(Mandatory)]
    [guid]$McpIdentityClientId,

    [string]$DatabaseName = 'TransferDemo',

    [switch]$CreateDatabase
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sqlcmdCandidates = @(
    'C:\Program Files\SqlCmd\sqlcmd.exe',
    (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
) | Where-Object { $_ -and (Test-Path $_) }
$sqlcmd = $sqlcmdCandidates | Select-Object -First 1
if (-not $sqlcmd) {
    throw 'Modern sqlcmd is required. Install winget package Microsoft.Sqlcmd before deploying the demo database.'
}

$sqlRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/data/sql'
$migrations = @(
    @{ Script = '001_schema.sql'; Database = $DatabaseName },
    @{ Script = '002_seed.sql'; Database = $DatabaseName },
    @{ Script = '003_contract.sql'; Database = $DatabaseName },
    @{ Script = '004_security.sql'; Database = $DatabaseName }
)

if ($CreateDatabase) {
    $migrations = @(@{ Script = '000_create_database.sql'; Database = 'master' }) + $migrations
}

foreach ($migration in $migrations) {
    $scriptPath = Join-Path $sqlRoot $migration.Script
    Write-Host "Applying $($migration.Script)..."
    & $sqlcmd -S $Server -d $migration.Database --authentication-method ActiveDirectoryAzCli -N true -b -I -i $scriptPath -v "DatabaseName=$DatabaseName" "McpIdentityName=$McpIdentityName" "McpIdentityClientId=$McpIdentityClientId"
    if ($LASTEXITCODE -ne 0) {
        throw "Database deployment failed while applying $($migration.Script)."
    }
}

Write-Host "Demo database '$DatabaseName' deployed successfully."