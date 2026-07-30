[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Server,

    [Parameter(Mandatory)]
    [string]$McpIdentityName,

    [Parameter(Mandatory)]
    [guid]$McpIdentityObjectId,

    [string]$DatabaseName = 'TransferDemo'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    throw 'sqlcmd is required. Install the Microsoft sqlcmd utility before deploying the demo database.'
}

$sqlRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/data/sql'
$scripts = @(
    '000_create_database.sql',
    '001_schema.sql',
    '002_seed.sql',
    '003_contract.sql',
    '004_security.sql'
)

foreach ($script in $scripts) {
    $scriptPath = Join-Path $sqlRoot $script
    Write-Host "Applying $script..."
    & sqlcmd -S $Server -d master -G -b -I -i $scriptPath -v "DatabaseName=$DatabaseName" "McpIdentityName=$McpIdentityName" "McpIdentityObjectId=$McpIdentityObjectId"
    if ($LASTEXITCODE -ne 0) {
        throw "Database deployment failed while applying $script."
    }
}

Write-Host "Demo database '$DatabaseName' deployed successfully."