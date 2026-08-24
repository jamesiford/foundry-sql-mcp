# Troubleshooting SQL MCP Container Apps and Foundry authentication

Use this guide when the SQL MCP Container App starts and then appears to stop, the agent cannot call SQL MCP tools, or Foundry returns `401 Unauthorized` when connecting to the `/mcp` endpoint.

The checks are ordered by failure boundary:

1. Container App scale and runtime health.
2. Data API builder (DAB) entity contract and deployed image.
3. Foundry agent tool allowlist.
4. Foundry-to-MCP Entra authentication.

Run commands from PowerShell in the repository root unless otherwise noted.

## 1. Confirm whether the Container App scaled to zero or crashed

Set the application values:

```powershell
$rg = "<resource-group>"
$app = "<container-app-name>"
```

Check the current scale settings, image, revision, and FQDN:

```powershell
az containerapp show `
  --name $app `
  --resource-group $rg `
  --query "{minReplicas:properties.template.scale.minReplicas,maxReplicas:properties.template.scale.maxReplicas,latestRevision:properties.latestRevisionName,image:properties.template.containers[0].image,fqdn:properties.configuration.ingress.fqdn}" `
  -o json
```

If `minReplicas` is `0`, the app can scale down after idle time. Keep the SQL MCP endpoint warm for Foundry by setting at least one replica:

```powershell
az containerapp update `
  --name $app `
  --resource-group $rg `
  --min-replicas 1 `
  --max-replicas 1
```

If `minReplicas` is already `1`, inspect revision logs before changing configuration:

```powershell
az containerapp logs show `
  --name $app `
  --resource-group $rg `
  --tail 200
```

Common startup failures:

| Log symptom | Likely issue | Fix |
|---|---|---|
| SQL timeout, no route, or connection failure | Network path to SQL is blocked, DNS is wrong, or the SQL hostname and port do not match | Verify VNet path, DNS, SQL hostname, and port |
| `Login failed for user '<token-identified principal>'` | MCP managed identity is not mapped in SQL or is missing grants | Re-check the SQL user, role membership, and named-object grants |
| `Cannot obtain schema for entity ...` | DAB points to a missing object or an object not granted to the MCP identity | Fix the entity `source` in `dab-config.json` or the SQL grant |
| Missing primary key | A DAB entity has no stable field marked `primary-key` | Mark exactly one stable field as `"primary-key": true` |
| JWT audience or issuer error | The image was built with the wrong MCP app client ID or tenant ID | Rebuild the MCP image with the correct values |

For SQL Managed Instance, the hostname and port must match the endpoint:

```text
Private SQL MI endpoint:
Server=tcp:<mi-name>.<dns-zone>.database.windows.net,1433

Public SQL MI endpoint, only if explicitly enabled:
Server=tcp:<mi-name>.public.<dns-zone>.database.windows.net,3342
```

Mixing the private hostname with port `3342`, or the public hostname with port `1433`, produces generic connection failures that are easy to mistake for identity issues.

## 2. Confirm the local DAB MCP contract

Inspect the entities and globally enabled MCP tools:

```powershell
$dab = Get-Content .\src\mcp-server\dab-config.json -Raw | ConvertFrom-Json

Write-Host "DAB entities:"
$dab.entities.PSObject.Properties.Name

Write-Host "Global MCP tools:"
$dab.runtime.mcp.'dml-tools' | ConvertTo-Json -Depth 10
```

If you adapted the demo to a customer-specific entity, also inspect that entity directly:

```powershell
$entityName = "<EntityName>"
$dab.entities.$entityName | ConvertTo-Json -Depth 20
```

Expected:

- The intended customer entity appears in the entity list.
- `describe-entities`, `read-records`, and `aggregate-records` are enabled when the agent should query approved views.
- The entity has explicit field names and field descriptions.
- One stable field is marked as the primary key.
- The entity has `"mcp": { "dml-tools": true, "custom-tool": false }` for read/aggregate access.

If the entity does not appear here, the prompt or agent instructions may have been updated without updating the SQL MCP server contract.

## 3. Confirm the deployed image matches the expected image

Load the active `azd` environment values:

```powershell
$values = azd env get-values --output json | ConvertFrom-Json
```

Compare the image running in Container Apps with the image expected by the environment:

```powershell
Write-Host "Image currently deployed to Container App:"
az containerapp show `
  --name $app `
  --resource-group $rg `
  --query "properties.template.containers[0].image" `
  -o tsv

Write-Host "Image expected by azd environment:"
$values.MCP_CONTAINER_IMAGE
```

The two values should match. If they do not, the Container App is likely running an older DAB configuration.

Rebuild and redeploy the MCP image:

```powershell
.\scripts\build-demo-mcp.ps1 `
  -RegistryName $values.AZURE_CONTAINER_REGISTRY_NAME `
  -McpApplicationId $values.MCP_AUTH_APP_ID `
  -TenantId $values.AZURE_TENANT_ID

$values = azd env get-values --output json | ConvertFrom-Json

az containerapp update `
  --name $app `
  --resource-group $rg `
  --image $values.MCP_CONTAINER_IMAGE
```

Re-run the image comparison after the update.

## 4. Confirm the latest Foundry agent tool allowlist

The agent instructions are not the tool contract. The registered agent version must also allow the MCP tools it is expected to call.

```powershell
$agentName = "transfer-agent-sql-mcp-demo"
$env:AZURE_AI_PROJECT_ENDPOINT = $values.AZURE_AI_PROJECT_ENDPOINT

.\.venv\Scripts\python.exe -c @"
import json
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

client = AIProjectClient(
    endpoint='$env:AZURE_AI_PROJECT_ENDPOINT',
    credential=DefaultAzureCredential()
)

versions = list(client.agents.list_versions('$agentName', limit=1, order='desc'))
agent = versions[0].as_dict()

print(json.dumps({
    'name': agent.get('name'),
    'version': agent.get('version'),
    'tools': agent.get('definition', {}).get('tools', [])
}, indent=2))
"@
```

Expected for read-only view access:

```text
describe_entities
read_records
aggregate_records
```

If the allowlist still contains only demo-specific tools after adapting the SQL MCP contract, update `ALLOWED_TOOLS` in `src\agent\register_agent.py`, then register a new agent version:

```powershell
.\scripts\register-demo-agent.ps1
```

Also update `src\agent\instructions.txt` and `src\agent\smoke_test_agent.py` so the instructions and validation prompts match the adapted data contract.

## 5. Test live tool discovery through the agent

Ask the active agent to call schema discovery:

```powershell
.\.venv\Scripts\python.exe -c @"
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

client = AIProjectClient(
    endpoint='$env:AZURE_AI_PROJECT_ENDPOINT',
    credential=DefaultAzureCredential()
)

openai_client = client.get_openai_client()

response = openai_client.responses.create(
    input='Use describe_entities now and list the exact entities and fields you can see. Do not answer from instructions.',
    extra_body={
        'agent_reference': {
            'name': '$agentName',
            'type': 'agent_reference'
        }
    }
)

print(response.output_text)
"@
```

Interpret the result:

- If the response lists the intended customer entities and fields, the MCP contract is attached.
- If the response says the agent cannot call `describe_entities`, the MCP tool is not attached or not allowed on the active agent version.
- If the response lists the original transfer-demo entities, the deployed container or active agent version still points to the demo contract.

## 6. Troubleshoot `401 Unauthorized` from Foundry to `/mcp`

> The intended configuration of every component in this path is specified in [How Foundry-to-MCP authentication is supposed to work](auth-chain-reference.md), and [`scripts/verify-auth-chain.ps1`](../scripts/verify-auth-chain.ps1) checks all of it in one pass.

An error like this means Foundry reached *something* that returned 401:

```text
Authentication failed when connecting to the MCP server ...
Response status code does not indicate success: 401 (Unauthorized)
```

Before working through the causes below, establish **which component** produced the 401 — DAB itself, or a layer in front of it. The two have no fixes in common, and the message looks identical either way. Call a path DAB does not protect, with no token:

```powershell
$fqdn = az containerapp show -n $app -g $rg --query "properties.configuration.ingress.fqdn" -o tsv
curl.exe -s -o NUL -w "%{http_code}\n" "https://$fqdn/api"
```

- **`404` (or `400`/`406`)** — the request reached DAB, so the 401 on `/mcp` is a token rejection. Continue with this section.
- **`401`** — something in front of DAB is answering. DAB never returns 401 on an unauthenticated `/api`. Check Container Apps built-in authentication, which is not used by this design and must be off:

  ```powershell
  az containerapp auth show -n $app -g $rg --query '{enabled:platform.enabled, action:globalValidation.unauthenticatedClientAction}'
  az containerapp auth update -n $app -g $rg --enabled false   # if it is on
  ```

> **The container logs will not tell you this.** DAB logs nothing when it rejects a token — no `IDX` code, no request line, not even at `debug` log level. Verified against `data-api-builder:2.0.9`. Empty logs are what a token rejection looks like, so do not read them as evidence that traffic never arrived.

Most likely causes, once you have confirmed DAB is the one returning 401:

1. The MCP Entra application emits **v1** tokens because `api.requestedAccessTokenVersion` is unset. This is the Entra default and it breaks both the `aud` and `iss` claims at once. Check with `az ad app show --id <app-id> --query 'api.requestedAccessTokenVersion'` — it must return `2`. See [Required access](demo-portal-runbook.md#required-access).
2. The Foundry MCP connection is not using Microsoft Entra project managed identity authentication.
3. The Foundry connection audience is wrong.
4. The DAB image was built with the wrong MCP app client ID or tenant ID — or with the committed placeholders still in place, in which case no token can ever validate.
5. The Foundry project managed identity does not have the `Mcp.Invoke` app role assignment on the MCP Enterprise Application.
6. The active agent version points to an older MCP connection.
7. More than one Container App exists and the connection points at a different one than you are inspecting. Confirm with `az containerapp list -g $rg --query "[].{name:name, fqdn:properties.configuration.ingress.fqdn}" -o table` and match the FQDN against the agent's error message.

### 6.1 Confirm the MCP endpoint URL

The Foundry connection target should be:

```text
https://<container-app-fqdn>/mcp
```

Check the Container App FQDN:

```powershell
az containerapp show `
  --name $app `
  --resource-group $rg `
  --query "properties.configuration.ingress.fqdn" `
  -o tsv
```

Build the expected endpoint:

```powershell
"https://$(az containerapp show --name $app --resource-group $rg --query "properties.configuration.ingress.fqdn" -o tsv)/mcp"
```

Do not use `/api`, an extra path segment, or a query string.

### 6.2 Confirm the audience values

The Foundry MCP connection audience should be:

```text
api://<mcp-application-client-id>
```

The DAB JWT audience inside the built image should be the bare client ID:

```text
<mcp-application-client-id>
```

These are intentionally different.

Print the expected Foundry audience:

```powershell
$values = azd env get-values --output json | ConvertFrom-Json
"api://$($values.MCP_AUTH_APP_ID)"
```

Then inspect the MCP connection in the Foundry portal:

```text
Foundry project > Build > Tools > MCP connection
```

Expected connection settings:

```text
Authentication: Microsoft Entra / project managed identity
Audience: api://<mcp-application-client-id>
Target: https://<container-app-fqdn>/mcp
```

### 6.3 Rebuild the image with the real app and tenant IDs

The committed `dab-config.json` intentionally contains placeholders:

```json
"audience": "00000000-0000-0000-0000-000000000000"
"issuer": "https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111/v2.0"
```

The build script replaces those placeholders in the generated image. Rebuild and redeploy if the image may have been built with incorrect values:

```powershell
$values = azd env get-values --output json | ConvertFrom-Json

.\scripts\build-demo-mcp.ps1 `
  -RegistryName $values.AZURE_CONTAINER_REGISTRY_NAME `
  -McpApplicationId $values.MCP_AUTH_APP_ID `
  -TenantId $values.AZURE_TENANT_ID

$values = azd env get-values --output json | ConvertFrom-Json

az containerapp update `
  --name $app `
  --resource-group $rg `
  --image $values.MCP_CONTAINER_IMAGE
```

### 6.4 Reconcile the Entra app role assignment

The Foundry project managed identity must have the `Mcp.Invoke` application role assignment on the MCP Enterprise Application.

```powershell
$values = azd env get-values --output json | ConvertFrom-Json

.\scripts\setup-demo-entra.ps1 `
  -ProjectPrincipalId $values.AZURE_AI_PROJECT_PRINCIPAL_ID `
  -TenantId $values.AZURE_TENANT_ID
```

If the command fails with a permissions error, the operator likely lacks permission to update the Entra application, service principal, or app role assignments.

### 6.5 Reconcile the Foundry connection and agent version

If the MCP connection was created manually, reconcile it through the repository deployment path so the connection uses the expected authentication mode, audience, and endpoint:

```powershell
azd provision --environment foundry-sql-mcp-demo --no-prompt
```

Use the actual environment name if it is not `foundry-sql-mcp-demo`.

Then register a new agent version:

```powershell
.\scripts\register-demo-agent.ps1
```

Run the live `describe_entities` test again after these steps.

