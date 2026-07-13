[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$requiredPaths = @(
    'azure.yaml',
    'infra/main.bicep',
    'infra/main.parameters.json',
    'docs/architecture.md',
    'docs/security.md',
    'src/agent/README.md',
    'src/data/README.md',
    'src/mcp-server/README.md'
)

foreach ($relativePath in $requiredPaths) {
    $fullPath = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Required scaffold file is missing: $relativePath"
    }
}

$parametersPath = Join-Path $repoRoot 'infra/main.parameters.json'
Get-Content -LiteralPath $parametersPath -Raw | ConvertFrom-Json | Out-Null

$mainBicep = Join-Path $repoRoot 'infra/main.bicep'
& az bicep build --file $mainBicep --stdout | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Bicep compilation failed.'
}

Write-Host 'Infrastructure smoke test passed.'
