[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RegistryName,
    [Parameter(Mandatory)]
    [string]$McpApplicationId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $repoRoot 'src/mcp-server'
$buildRoot = Join-Path $repoRoot '.dab/demo-mcp-build'
if (Test-Path $buildRoot) {
    Remove-Item $buildRoot -Recurse -Force
}
New-Item $buildRoot -ItemType Directory -Force | Out-Null

Copy-Item (Join-Path $sourceRoot 'Dockerfile') $buildRoot
Copy-Item (Join-Path $sourceRoot '.dockerignore') $buildRoot
$config = Get-Content (Join-Path $sourceRoot 'dab-config.json') -Raw
$config = $config.Replace('00000000-0000-0000-0000-000000000000', $McpApplicationId)
$generatedConfig = Join-Path $buildRoot 'dab-config.json'
Set-Content $generatedConfig $config -NoNewline

$parsed = Get-Content $generatedConfig -Raw | ConvertFrom-Json
if ($parsed.runtime.host.authentication.jwt.audience -ne $McpApplicationId) {
    throw "Generated DAB audience doesn't match the MCP application ID."
}

$buildContent = (Get-Content (Join-Path $buildRoot 'Dockerfile') -Raw) + "`n" + (Get-Content $generatedConfig -Raw)
$hashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
try {
    $buildHashBytes = $hashAlgorithm.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($buildContent))
} finally {
    $hashAlgorithm.Dispose()
}
$buildHash = ([System.BitConverter]::ToString($buildHashBytes) -replace '-', '').Substring(0, 12).ToLowerInvariant()
$imageTag = "2.0.9-$buildHash"
$loginServer = az acr show --name $RegistryName --query loginServer -o tsv
if ($LASTEXITCODE -ne 0) {
    throw "Container registry '$RegistryName' was not found."
}
$image = "$loginServer/sql-mcp:$imageTag"
$existingTag = az acr repository show-tags --name $RegistryName --repository sql-mcp --query "[?@=='$imageTag'] | [0]" -o tsv 2>$null
if ($LASTEXITCODE -eq 0 -and $existingTag -eq $imageTag) {
    azd env set MCP_CONTAINER_IMAGE $image
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to store the existing MCP image in the azd environment.'
    }
    Write-Host "Reusing existing MCP image: $image"
    return
}

az acr build --registry $RegistryName --image "sql-mcp:$imageTag" $buildRoot
if ($LASTEXITCODE -ne 0) {
    throw 'ACR build failed.'
}

azd env set MCP_CONTAINER_IMAGE $image
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to store the built MCP image in the azd environment.'
}
Write-Host "Built and configured MCP image: $image"