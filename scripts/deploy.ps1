[CmdletBinding()]
param(
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$mainBicep = Join-Path $repoRoot 'infra/main.bicep'

& az bicep build --file $mainBicep --stdout | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Bicep validation failed.'
}

Write-Host 'Bicep validation passed.'

if (-not $ValidateOnly) {
    throw 'Deployment remains blocked until Phase 2 preflight, what-if, and azure-validate complete. Use the Azure deployment workflow after validation.'
}
