[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($commandName in @('az', 'azd')) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "Required command '$commandName' was not found on PATH."
    }
}

Write-Host 'Required commands are available.'

foreach ($commandName in @('docker', 'dab')) {
    if (Get-Command $commandName -ErrorAction SilentlyContinue) {
        Write-Host "Optional command '$commandName' is available."
    }
    else {
        Write-Host "Optional command '$commandName' is not installed; it is not required for Phase 1."
    }
}

Write-Host 'No packages, credentials, or Azure resources were changed.'
