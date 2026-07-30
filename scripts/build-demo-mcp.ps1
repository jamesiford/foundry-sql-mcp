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
$config = $config.Replace('api://00000000-0000-0000-0000-000000000000', "api://$McpApplicationId")
$generatedConfig = Join-Path $buildRoot 'dab-config.json'
Set-Content $generatedConfig $config -NoNewline

$parsed = Get-Content $generatedConfig -Raw | ConvertFrom-Json
if ($parsed.runtime.host.authentication.jwt.audience -ne "api://$McpApplicationId") {
    throw "Generated DAB audience doesn't match the MCP application ID."
}

$gitSuffix = git rev-parse --short HEAD
$imageTag = "2.0.9-$gitSuffix"
az acr build --registry $RegistryName --image "sql-mcp:$imageTag" $buildRoot
if ($LASTEXITCODE -ne 0) {
    throw 'ACR build failed.'
}

$loginServer = az acr show --name $RegistryName --query loginServer -o tsv
$image = "$loginServer/sql-mcp:$imageTag"
azd env set MCP_CONTAINER_IMAGE $image
Write-Host "Built and configured MCP image: $image"