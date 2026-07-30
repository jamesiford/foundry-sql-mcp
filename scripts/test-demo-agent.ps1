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
if ([string]::IsNullOrWhiteSpace($values.AZURE_AI_PROJECT_ENDPOINT)) {
    throw 'AZURE_AI_PROJECT_ENDPOINT is missing from the active azd environment.'
}
[Environment]::SetEnvironmentVariable('AZURE_AI_PROJECT_ENDPOINT', $values.AZURE_AI_PROJECT_ENDPOINT, 'Process')

& $python (Join-Path $repoRoot 'src/agent/smoke_test_agent.py')
if ($LASTEXITCODE -ne 0) {
    throw 'Prompt-agent smoke test failed.'
}