[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$python = Join-Path $repoRoot '.venv/Scripts/python.exe'
if (-not (Test-Path $python)) {
    throw 'Workspace .venv is missing. Configure Python and install src/agent/requirements.txt.'
}

$values = azd env get-values --output json | ConvertFrom-Json
foreach ($name in @('AZURE_AI_PROJECT_ENDPOINT', 'AZURE_AI_MODEL_DEPLOYMENT_NAME', 'MCP_ENDPOINT', 'MCP_PROJECT_CONNECTION_NAME')) {
    $value = $values.$name
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "azd value $name is missing. Complete the second infrastructure provision before registering the agent."
    }
    [Environment]::SetEnvironmentVariable($name, $value, 'Process')
}

& $python (Join-Path $repoRoot 'src/agent/register_agent.py')
if ($LASTEXITCODE -ne 0) {
    throw 'Prompt-agent registration failed.'
}