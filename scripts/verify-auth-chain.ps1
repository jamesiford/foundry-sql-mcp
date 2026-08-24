<#
.SYNOPSIS
    Verify every hop in the Foundry -> SQL MCP authentication chain.

.DESCRIPTION
    A 401 from the agent can originate at any of seven places, and the message is
    identical for all of them. This script reports the observed state of each hop
    against the contract the runbook defines, so the failing hop can be identified
    without guessing.

    It is read-only. It creates nothing and changes nothing.

.EXAMPLE
    ./scripts/verify-auth-chain.ps1 -ResourceGroup rg-gla-mcp -ContainerApp ca-sqlmcp -McpAppId <guid>

.EXAMPLE
    ./scripts/verify-auth-chain.ps1 -ResourceGroup rg-gla-mcp -ContainerApp ca-sqlmcp `
      -McpAppId <guid> -ProjectPrincipalId <guid>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$ContainerApp,
    [Parameter(Mandatory)][string]$McpAppId,
    [string]$ProjectPrincipalId,
    [string]$TenantId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$script:pass = 0
$script:fail = 0
$script:warn = 0

function Write-Head($n, $t) {
    Write-Host ''
    Write-Host ("  {0}. {1}" -f $n, $t) -ForegroundColor Cyan
    Write-Host ("  " + ('-' * 66)) -ForegroundColor DarkGray
}
function Write-Pass($m) { $script:pass++; Write-Host "     PASS  $m" -ForegroundColor Green }
function Write-Fail($m) { $script:fail++; Write-Host "     FAIL  $m" -ForegroundColor Red }
function Write-Warn($m) { $script:warn++; Write-Host "     WARN  $m" -ForegroundColor Yellow }
function Write-Info($m) { Write-Host "           $m" -ForegroundColor DarkGray }

function Get-Json {
    param([string[]]$Arguments)
    $raw = & az @Arguments 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) { return $null }
    try { return ($raw | ConvertFrom-Json) } catch { return $null }
}

Write-Host ''
Write-Host '  Foundry -> SQL MCP authentication chain' -ForegroundColor White
Write-Host '  Read-only. Nothing is created or modified.' -ForegroundColor DarkGray

if (-not $TenantId) { $TenantId = (Get-Json @('account','show','-o','json')).tenantId }

# ---------------------------------------------------------------- 1. Entra app
Write-Head 1 'Entra application (the MCP API and its token shape)'

$app = Get-Json @('ad','app','show','--id',$McpAppId,'-o','json')
if (-not $app) {
    Write-Fail "Application $McpAppId not found in tenant $TenantId."
    Write-Info 'Everything downstream depends on this. Stop here.'
} else {
    Write-Pass "Application found: $($app.displayName)"

    $tokenVersion = $null
    if ($app.PSObject.Properties['api'] -and $app.api) { $tokenVersion = $app.api.requestedAccessTokenVersion }
    if ($tokenVersion -eq 2) {
        Write-Pass 'requestedAccessTokenVersion = 2'
    } else {
        Write-Fail "requestedAccessTokenVersion = '$tokenVersion' (must be 2)"
        Write-Info 'v1 issues aud=api://<id> and iss=sts.windows.net/<tid>/.'
        Write-Info 'DAB expects the bare GUID and the /v2.0 issuer. Both claims fail.'
    }

    $expectedUri = "api://$McpAppId"
    if ($app.identifierUris -contains $expectedUri) {
        Write-Pass "identifierUri present: $expectedUri"
    } else {
        Write-Fail "identifierUri $expectedUri missing. Found: $($app.identifierUris -join ', ')"
        Write-Info 'Foundry requests this exact value as the audience.'
    }

    $role = @($app.appRoles | Where-Object { $_.value -eq 'Mcp.Invoke' }) | Select-Object -First 1
    if ($role) {
        if ($role.isEnabled) { Write-Pass 'App role Mcp.Invoke present and enabled' }
        else { Write-Fail 'App role Mcp.Invoke exists but is disabled' }
        if ($role.allowedMemberTypes -contains 'Application') { Write-Pass 'Mcp.Invoke allows Application members' }
        else { Write-Fail "Mcp.Invoke allowedMemberTypes = $($role.allowedMemberTypes -join ',') (needs Application)" }
    } else {
        Write-Fail 'App role Mcp.Invoke not defined'
    }
}

# ------------------------------------------- 2. Service principal + assignment
Write-Head 2 'Service principal and the caller allowlist'

$sp = Get-Json @('ad','sp','show','--id',$McpAppId,'-o','json')
if (-not $sp) {
    Write-Fail 'No service principal (enterprise application) for this app registration.'
    Write-Info 'Entra cannot issue tokens for a resource with no service principal.'
} else {
    Write-Pass "Service principal found: $($sp.id)"
    if ($sp.appRoleAssignmentRequired) {
        Write-Pass 'appRoleAssignmentRequired = true (only assigned identities get a token)'
    } else {
        Write-Warn 'appRoleAssignmentRequired = false'
        Write-Info 'Not a 401 cause, but any tenant workload could request a token.'
    }

    if ($ProjectPrincipalId) {
        $assignments = Get-Json @('rest','--method','get','--url',"https://graph.microsoft.com/v1.0/servicePrincipals/$ProjectPrincipalId/appRoleAssignments",'--query','value','-o','json')
        $match = @($assignments | Where-Object { $_.resourceId -eq $sp.id }) | Select-Object -First 1
        if ($match) {
            Write-Pass 'Foundry project identity holds an app role on this resource'
            Write-Info "appRoleId $($match.appRoleId)"
        } else {
            Write-Fail 'Foundry project identity has NO app role assignment on this resource'
            Write-Info 'With appRoleAssignmentRequired = true, Entra refuses to issue the token.'
        }
    } else {
        Write-Warn 'ProjectPrincipalId not supplied - skipping the assignment check'
        Write-Info 'Pass -ProjectPrincipalId <foundry project principal id> to include it.'
    }
}

# ------------------------------------------------------------ 3. Container App
Write-Head 3 'Container App ingress'

$ca = Get-Json @('containerapp','show','-n',$ContainerApp,'-g',$ResourceGroup,'-o','json')
$fqdn = $null
if (-not $ca) {
    Write-Fail "Container App '$ContainerApp' not found in '$ResourceGroup'."
} else {
    $fqdn = $ca.properties.configuration.ingress.fqdn
    if ($fqdn) { Write-Pass "FQDN: $fqdn" } else { Write-Fail 'No ingress FQDN - ingress may be disabled' }
    if ($ca.properties.configuration.ingress.external) { Write-Pass 'Ingress is external' }
    else { Write-Fail 'Ingress is internal - Foundry is public and cannot reach it' }
    Write-Info "Target port: $($ca.properties.configuration.ingress.targetPort)"
    Write-Info "Active revision: $($ca.properties.latestReadyRevisionName)"

    $minR = $null
    try { $minR = $ca.properties.template.scale.minReplicas } catch { }
    if ($minR -eq 0 -or $null -eq $minR) {
        Write-Warn 'minReplicas is 0 - cold starts cause delays (never 401)'
    } else { Write-Pass "minReplicas = $minR" }
}

$others = Get-Json @('containerapp','list','-g',$ResourceGroup,'--query','[].{name:name,fqdn:properties.configuration.ingress.fqdn}','-o','json')
if ($others -and @($others).Count -gt 1) {
    Write-Warn "$(@($others).Count) Container Apps exist in this resource group"
    foreach ($o in $others) { Write-Info "$($o.name)  ->  $($o.fqdn)" }
    Write-Info 'The Foundry connection target must match the app you are inspecting.'
}

# ------------------------------------------------- 4. Platform auth (Easy Auth)
Write-Head 4 'Container Apps built-in authentication (must be OFF)'

$auth = Get-Json @('containerapp','auth','show','-n',$ContainerApp,'-g',$ResourceGroup,'-o','json')
$platformEnabled = $false
if ($auth -and $auth.PSObject.Properties['platform'] -and $auth.platform) {
    $platformEnabled = [bool]$auth.platform.enabled
}
if (-not $ca) {
    Write-Warn 'Container App not found - cannot evaluate built-in authentication'
} elseif ($platformEnabled) {
    Write-Fail 'Built-in authentication is ENABLED'
    Write-Info 'This returns 401 before traffic reaches the container. DAB never sees the call.'
    Write-Info "Disable: az containerapp auth update -n $ContainerApp -g $ResourceGroup --enabled false"
} else {
    Write-Pass 'Built-in authentication is off - DAB performs its own validation'
}

# ----------------------------------------------------- 5. Live response probe
Write-Head 5 'Live probe: which component answers?'

if (-not $fqdn) {
    Write-Warn 'No FQDN - skipping live probe'
} else {
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    function Get-Code($url) {
        if ($curl) { return (& $curl.Source -s -o NUL -w '%{http_code}' --max-time 20 $url 2>$null) }
        try { return [string][int](Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20).StatusCode }
        catch { if ($_.Exception.Response) { return [string][int]$_.Exception.Response.StatusCode } else { return 'ERR' } }
    }

    $apiCode = Get-Code "https://$fqdn/api"
    Write-Info "unauthenticated GET /api  -> HTTP $apiCode"

    switch ($apiCode) {
        '401' {
            Write-Fail 'Something IN FRONT of DAB is answering'
            Write-Info 'DAB returns 404 on an unauthenticated /api, never 401.'
            Write-Info 'Look at built-in authentication, or a gateway/WAF in the path.'
        }
        { $_ -in @('404','400','406','403') } {
            Write-Pass "Request reaches DAB (HTTP $apiCode is a DAB response)"
            Write-Info 'So a 401 on /mcp is DAB rejecting the token - see checks 1, 2 and 6.'
        }
        '200' { Write-Warn 'HTTP 200 unauthenticated - REST may be exposed anonymously' }
        default { Write-Warn "Unexpected code $apiCode - the app may be down or still starting" }
    }

    $mcpCode = Get-Code "https://$fqdn/mcp"
    Write-Info "unauthenticated GET /mcp  -> HTTP $mcpCode"
    if ($mcpCode -eq '401') { Write-Info 'Expected: DAB rejects unauthenticated MCP calls.' }
}

# --------------------------------------------------- 6. What is in the image
Write-Head 6 'DAB configuration inside the running container'

$cfgRaw = & az containerapp exec -n $ContainerApp -g $ResourceGroup --command "cat /App/dab-config.json" 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($cfgRaw)) {
    Write-Warn 'Could not read the config from the container'
    Write-Info 'az containerapp exec needs an interactive terminal; run it manually if this fails:'
    Write-Info "az containerapp exec -n $ContainerApp -g $ResourceGroup --command `"cat /App/dab-config.json`""
} else {
    $start = $cfgRaw.IndexOf('{')
    $stop  = $cfgRaw.LastIndexOf('}')
    $cfg = $null
    if ($start -ge 0 -and $stop -gt $start) {
        try { $cfg = $cfgRaw.Substring($start, $stop - $start + 1) | ConvertFrom-Json } catch { }
    }
    if (-not $cfg) {
        Write-Warn 'Config retrieved but could not be parsed as JSON'
    } else {
        $jwt = $cfg.runtime.host.authentication.jwt
        if ($jwt.audience -eq $McpAppId) {
            Write-Pass "DAB audience matches the application: $($jwt.audience)"
        } elseif ($jwt.audience -like '0000*') {
            Write-Fail "DAB audience is still the placeholder: $($jwt.audience)"
            Write-Info 'The image was built from the committed config. No token can ever validate.'
            Write-Info 'Rebuild with ./scripts/build-demo-mcp.ps1 and deploy a new revision.'
        } else {
            Write-Fail "DAB audience '$($jwt.audience)' does not match app id '$McpAppId'"
        }

        $expectedIssuer = "https://login.microsoftonline.com/$TenantId/v2.0"
        if ($jwt.issuer -eq $expectedIssuer) { Write-Pass "DAB issuer matches tenant: $($jwt.issuer)" }
        elseif ($jwt.issuer -like '*1111-1111*') { Write-Fail "DAB issuer is still the placeholder: $($jwt.issuer)" }
        else { Write-Fail "DAB issuer '$($jwt.issuer)' != expected '$expectedIssuer'" }

        if ($cfg.runtime.host.authentication.provider -eq 'EntraID') { Write-Pass 'Provider is EntraID' }
        else { Write-Fail "Provider is '$($cfg.runtime.host.authentication.provider)' (expected EntraID)" }

        if ($cfg.runtime.mcp.enabled) { Write-Pass "MCP enabled at path $($cfg.runtime.mcp.path)" }
        else { Write-Fail 'MCP is disabled in the running config' }

        Write-Host ''
        Write-Info 'Entity permissions (the authorization hop, distinct from authentication):'
        $anyAuthenticated = $false
        foreach ($p in $cfg.entities.PSObject.Properties) {
            $roles = @($p.Value.permissions | ForEach-Object { $_.role })
            if ($roles -contains 'authenticated' -or $roles -contains 'Mcp.Invoke') { $anyAuthenticated = $true }
            Write-Info ("{0,-34} roles: {1}" -f $p.Name, ($roles -join ', '))
        }
        if (-not $anyAuthenticated) {
            Write-Fail 'No entity grants authenticated or Mcp.Invoke'
            Write-Info 'A valid token would still fail with: Authorization Failure: Access Not Allowed'
        }
    }
}

# ---------------------------------------------------------------- Summary
Write-Host ''
Write-Host ('  ' + ('=' * 66)) -ForegroundColor DarkGray
Write-Host ("  PASS {0}    FAIL {1}    WARN {2}" -f $script:pass, $script:fail, $script:warn) -ForegroundColor White
if ($script:fail -eq 0) {
    Write-Host '  No contract violation found in the checks above.' -ForegroundColor Green
    Write-Host '  If the agent still returns 401, check the Foundry connection itself:' -ForegroundColor DarkGray
    Write-Host '  authType ProjectManagedIdentity, audience api://<app-id>, target https://<fqdn>/mcp' -ForegroundColor DarkGray
} else {
    Write-Host '  Fix the FAIL lines in order - earlier hops invalidate later ones.' -ForegroundColor Yellow
}
Write-Host ''
