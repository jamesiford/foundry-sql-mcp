# SQL MCP Public Demo Guide

This guide operates the `demo/public-evaluation` branch. It creates a disposable public Foundry Basic project, Azure SQL Database, and public SQL MCP Server. It does not deploy Foundry IQ or Azure AI Search. See the [portal-first public setup](demo-portal-runbook.md) for click-by-click resource configuration and [SQL backend options](sql-backend-options.md) for customer SQL MI and on-premises SQL Server requirements.

## Safety boundary

- Use synthetic data only.
- The demo SQL logical server uses `SecuredByPerimeter` on TCP `1433` and must contain synthetic data only.
- An enforced Network Security Perimeter allows Azure-resource traffic from the demo subscription plus deployment-client source addresses; no VNet or private endpoint is deployed.
- SQL authentication is disabled; access uses Entra and managed identity.
- Keep Entra authentication, `Mcp.Invoke`, managed identity, `mcp_reader`, and read-only DAB tools enabled.
- Run cleanup after the demonstration.

## 1. Select the branch and Azure context

```powershell
git switch demo/public-evaluation
az account set --subscription 49d5f6b0-70f2-4563-acdc-9a31d2eee119
az account show --query "{user:user.name,tenant:tenantId,subscription:id}" -o table
azd auth login --check-status
```

Expected tenant: `16b3c013-d300-468d-ac64-7eda0820b6d3`.

## 2. Configure the demo environment

Use the region recorded in the validated deployment plan and choose an expiration date:

```powershell
./scripts/setup-demo-environment.ps1 `
  -Location eastus2 `
  -SqlLocation centralus `
  -ExpirationDate <yyyy-mm-dd>
```

Run local validation:

```powershell
./scripts/test-demo.ps1
azd provision --preview --no-prompt
```

Review the preview before deployment.

## 3. Bootstrap public demo infrastructure

After deployment confirmation:

```powershell
azd provision --no-prompt
$values = azd env get-values --output json | ConvertFrom-Json
```

The first provision creates Foundry Basic, the model, ACR, the public Container Apps environment, UAMI, monitoring, Azure SQL Database, and its enforced Network Security Perimeter. It does not create the SQL MCP Container App because no image is configured yet.

## 4. Configure MCP Entra authentication

```powershell
./scripts/setup-demo-entra.ps1 `
  -ProjectPrincipalId $values.AZURE_AI_PROJECT_PRINCIPAL_ID

$values = azd env get-values --output json | ConvertFrom-Json
```

This creates a dedicated Entra app, exposes `api://<app-id>`, defines application role `Mcp.Invoke`, requires app-role assignment on the resource service principal, assigns the role to the Foundry project identity, and stores only non-secret IDs/URIs in azd. The project connection uses the Application ID URI to request the token; DAB validates the resulting bare client-ID audience and tenant v2 issuer. DAB evaluates the call as its `authenticated` system role because Foundry doesn't send `X-MS-API-ROLE`; Entra app-role assignment is the caller allowlist.

## 5. Build the pinned DAB image

```powershell
./scripts/build-demo-mcp.ps1 `
  -RegistryName $values.AZURE_CONTAINER_REGISTRY_NAME `
  -McpApplicationId $values.MCP_AUTH_APP_ID
```

The generated build context is under ignored `.dab/`; the committed config retains a placeholder audience. The ACR image contains the real non-secret audience.

## 6. Deploy schema, data, and SQL authorization

Install the modern cross-platform sqlcmd client once if it isn't present:

```powershell
winget install --id Microsoft.Sqlcmd
```

```powershell
./scripts/deploy-demo-database.ps1 `
  -Server "$($values.AZURE_SQL_SERVER_FQDN),1433" `
  -McpIdentityName $values.AZURE_MCP_IDENTITY_NAME `
  -McpIdentityClientId $values.AZURE_MCP_IDENTITY_CLIENT_ID
```

The scripts are idempotent and create only synthetic data, approved views/procedures, `mcp_reader`, and the MCP UAMI contained user.

## 7. Deploy SQL MCP Container App and project connection

```powershell
azd provision --no-prompt
$values = azd env get-values --output json | ConvertFrom-Json
```

The second provision sees `MCP_CONTAINER_IMAGE` and creates the public Container App plus the `sql-mcp-demo` RemoteTool project connection.

Verify health and authentication:

```powershell
az containerapp show `
  --resource-group $values.AZURE_RESOURCE_GROUP `
  --name (az resource list --resource-group $values.AZURE_RESOURCE_GROUP --resource-type Microsoft.App/containerApps --query '[0].name' -o tsv) `
  --query "{state:properties.provisioningState,fqdn:properties.configuration.ingress.fqdn}" -o table
```

Anonymous and wrong-audience MCP calls must fail. Authenticated project-identity calls are validated when the agent invokes tools.

## 8. Register and test the prompt agent

```powershell
./scripts/register-demo-agent.ps1
./scripts/test-demo-agent.ps1
```

The agent is named `transfer-agent-sql-mcp-demo` and allowlists:

- `describe_entities`
- `read_records`
- `aggregate_records`
- `get_transfer_summary_by_client`
- `get_open_risk_alerts`
- `get_advisor_pipeline`

## 9. Open Foundry Playground

1. Browse to [Microsoft Foundry](https://ai.azure.com/).
2. Select project `project-foundry-sql-mcp-demo` or the actual project name from `AZURE_AI_PROJECT_NAME`.
3. Open **Build > Agents**.
4. Select `transfer-agent-sql-mcp-demo` and its latest version.
5. Open **Playground**.

Suggested prompts:

```text
Return the transfer summary for CLIENT-001.
```

```text
Show open High severity risk alerts.
```

```text
Summarize the transfer pipeline for advisor ADV-MIL-01.
```

The public demo project should open from the browser without VPN/private DNS. If the old private project is selected, it still returns `Public access is disabled`; switch to the new demo project.

## 10. Cleanup

```powershell
./scripts/cleanup-demo.ps1 -ConfirmCleanup
```

Cleanup deletes the demo RG, including its Azure SQL logical server/database, and removes the demo MCP Entra application. It does not modify the existing private Foundry/SQL MI resource group.