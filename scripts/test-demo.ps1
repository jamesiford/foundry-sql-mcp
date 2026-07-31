[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$requiredPaths = @(
    'infra/demo/main.bicep',
    'infra/demo/main.parameters.json',
    'src/mcp-server/dab-config.json',
    'src/mcp-server/Dockerfile',
    'src/agent/register_agent.py',
    'src/agent/smoke_test_agent.py',
    'src/agent/requirements.txt',
    'src/data/sql/004_security.sql'
)
foreach ($relativePath in $requiredPaths) {
    if (-not (Test-Path (Join-Path $repoRoot $relativePath) -PathType Leaf)) {
        throw "Required demo file is missing: $relativePath"
    }
}

$compiledTemplate = Join-Path ([System.IO.Path]::GetTempPath()) "foundry-sql-mcp-$([guid]::NewGuid()).json"
try {
    $bicepDiagnostics = az bicep build `
        --file (Join-Path $repoRoot 'infra/demo/main.bicep') `
        --outfile $compiledTemplate 2>&1 | Out-String
    $actionableDiagnostics = @(
        $bicepDiagnostics -split '\r?\n' |
            Where-Object { $_ -notmatch '^WARNING: A new Bicep release is available:' }
    ) -join [Environment]::NewLine
    if ($LASTEXITCODE -ne 0 -or $actionableDiagnostics -match '(?im)^\s*(warning|error)') {
        Write-Error $actionableDiagnostics
        throw 'Demo Bicep validation failed.'
    }
} finally {
    Remove-Item $compiledTemplate -Force -ErrorAction SilentlyContinue
}

Get-Content (Join-Path $repoRoot 'infra/demo/main.parameters.json') -Raw | ConvertFrom-Json | Out-Null
$dabConfig = Get-Content (Join-Path $repoRoot 'src/mcp-server/dab-config.json') -Raw | ConvertFrom-Json
if ($dabConfig.runtime.mcp.'dml-tools'.'create-record' -ne $false -or
    $dabConfig.runtime.mcp.'dml-tools'.'update-record' -ne $false -or
    $dabConfig.runtime.mcp.'dml-tools'.'delete-record' -ne $false -or
    $dabConfig.runtime.mcp.'dml-tools'.'execute-entity' -ne $false) {
    throw 'DAB write or generic execute tools are not disabled.'
}
foreach ($entity in $dabConfig.entities.PSObject.Properties) {
    $permissionRoles = @($entity.Value.permissions.role)
    if (@($permissionRoles | Where-Object { $_ -notin @('Mcp.Invoke', 'authenticated') }).Count -gt 0) {
        throw "Entity $($entity.Name) grants an unexpected DAB role."
    }
    if ('Mcp.Invoke' -notin $permissionRoles -or 'authenticated' -notin $permissionRoles) {
        throw "Entity $($entity.Name) must grant both MCP and authenticated DAB roles."
    }
    foreach ($permission in $entity.Value.permissions) {
        if ($permission.actions.action -match 'create|update|delete') {
            throw "Entity $($entity.Name) grants a write action."
        }
    }
}

$env:DATABASE_CONNECTION_STRING = 'Server=tcp:demo.invalid,1433;Initial Catalog=TransferDemo;Authentication=Active Directory Managed Identity;User Id=00000000-0000-0000-0000-000000000000;Encrypt=True;TrustServerCertificate=False;'
$dabOutput = dab validate --config (Join-Path $repoRoot 'src/mcp-server/dab-config.json') 2>&1 | Out-String
if ($dabOutput -notmatch 'The config satisfies the schema requirements' -or $dabOutput -match 'Total schema validation errors') {
    Write-Error $dabOutput
    throw 'DAB schema validation failed.'
}

& (Join-Path $PSScriptRoot 'test-demo-sql.ps1')

$python = Join-Path $repoRoot '.venv/Scripts/python.exe'
if (Test-Path $python) {
    & $python -m py_compile (Join-Path $repoRoot 'src/agent/register_agent.py') (Join-Path $repoRoot 'src/agent/smoke_test_agent.py')
    if ($LASTEXITCODE -ne 0) {
        throw 'Agent Python validation failed.'
    }
}

$dockerfile = Get-Content (Join-Path $repoRoot 'src/mcp-server/Dockerfile') -Raw
if ($dockerfile -notmatch 'data-api-builder:2\.0\.9') {
    throw 'DAB container image is not pinned to 2.0.9.'
}

Write-Host 'Public SQL MCP demo validation passed.'