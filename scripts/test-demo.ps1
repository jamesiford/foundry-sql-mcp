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

$bicepOutput = az bicep build --file (Join-Path $repoRoot 'infra/demo/main.bicep') --stdout 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or $bicepOutput -match 'WARNING|ERROR') {
    Write-Error $bicepOutput
    throw 'Demo Bicep validation failed.'
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
    foreach ($permission in $entity.Value.permissions) {
        if ($permission.role -ne 'Mcp.Invoke') {
            throw "Entity $($entity.Name) grants unexpected DAB role $($permission.role)."
        }
    }
}

$env:DATABASE_CONNECTION_STRING = 'Server=tcp:demo.invalid,3342;Initial Catalog=TransferDemo;Authentication=Active Directory Managed Identity;User Id=00000000-0000-0000-0000-000000000000;Encrypt=True;TrustServerCertificate=False;'
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