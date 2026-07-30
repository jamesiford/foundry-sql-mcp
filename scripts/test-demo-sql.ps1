[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$assemblyRoots = @(
    'C:\Program Files\Microsoft Visual Studio\18\Insiders',
    'C:\Program Files\Microsoft Visual Studio\18\Professional',
    'C:\Program Files\Microsoft SQL Server'
)

$scriptDomAssemblies = @(foreach ($root in $assemblyRoots) {
    if (Test-Path $root) {
        Get-ChildItem $root -Filter Microsoft.SqlServer.TransactSql.ScriptDom.dll -Recurse -ErrorAction SilentlyContinue
    }
})
$scriptDomAssembly = $scriptDomAssemblies | Select-Object -First 1

if (-not $scriptDomAssembly) {
    throw 'Microsoft.SqlServer.TransactSql.ScriptDom.dll was not found. Install SQL Server Data Tools to run SQL syntax validation.'
}

Add-Type -Path $scriptDomAssembly.FullName
$parser = [Microsoft.SqlServer.TransactSql.ScriptDom.TSql170Parser]::new($true)
$sqlRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/data/sql'
$allErrors = [System.Collections.Generic.List[string]]::new()

foreach ($file in Get-ChildItem $sqlRoot -Filter '*.sql' | Sort-Object Name) {
    $content = Get-Content $file.FullName -Raw
    $content = [regex]::Replace($content, '(?m)^:setvar.*\r?\n?', '')
    $content = $content.Replace('$(DatabaseName)', 'TransferDemo')
    $content = $content.Replace('$(McpIdentityName)', 'id-mcp-foundry-sql-mcp-demo')
    $content = $content.Replace('$(McpIdentityClientId)', '9e9b29a8-4f36-4f67-ba43-44a4fd505adf')
    $batches = [regex]::Split($content, '(?im)^\s*GO\s*(?:--.*)?$')

    for ($batchIndex = 0; $batchIndex -lt $batches.Count; $batchIndex++) {
        if ([string]::IsNullOrWhiteSpace($batches[$batchIndex])) {
            continue
        }

        $reader = [System.IO.StringReader]::new($batches[$batchIndex])
        $parseErrors = $null
        $parser.Parse($reader, [ref]$parseErrors) | Out-Null
        foreach ($parseError in $parseErrors) {
            $allErrors.Add("$($file.Name) batch $($batchIndex + 1), line $($parseError.Line), column $($parseError.Column): $($parseError.Message)")
        }
    }
}

if ($allErrors.Count -gt 0) {
    $allErrors | ForEach-Object { Write-Error $_ }
    throw "SQL syntax validation failed with $($allErrors.Count) error(s)."
}

Write-Host "SQL syntax validation passed for $((Get-ChildItem $sqlRoot -Filter '*.sql').Count) files."