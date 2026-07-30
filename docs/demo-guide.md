# SQL MCP Public Demo Guide

This guide operates the `demo/public-evaluation` branch. It creates a disposable public Foundry Basic project and public SQL MCP Server while reusing the existing synthetic SQL MI. It does not deploy Foundry IQ or Azure AI Search.

## Safety boundary

- Use synthetic data only.
- Do not run these commands against a production SQL MI.
- The SQL MI public endpoint and `AzureCloud` TCP `3342` NSG rule are temporary evaluation exceptions.
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
  -Location <validated-region> `
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

The first provision creates Foundry Basic, the model, ACR, the public Container Apps environment, UAMI, and monitoring. It does not create the SQL MCP Container App because no image is configured yet.

## 4. Configure MCP Entra authentication

```powershell
./scripts/setup-demo-entra.ps1 `
  -ProjectPrincipalId $values.AZURE_AI_PROJECT_PRINCIPAL_ID

$values = azd env get-values --output json | ConvertFrom-Json
```

This creates a dedicated Entra app, exposes `api://<app-id>`, defines application role `Mcp.Invoke`, assigns it to the Foundry project identity, and stores only non-secret IDs/URIs in azd.

## 5. Build the pinned DAB image

```powershell
./scripts/build-demo-mcp.ps1 `
  -RegistryName $values.AZURE_CONTAINER_REGISTRY_NAME `
  -McpApplicationId $values.MCP_AUTH_APP_ID
```

The generated build context is under ignored `.dab/`; the committed config retains a placeholder audience. The ACR image contains the real non-secret audience.

## 6. Enable temporary SQL MI demo access

```powershell
./scripts/configure-demo-sqlmi.ps1
$values = azd env get-values --output json | ConvertFrom-Json
```

This starts SQL MI, enables its public endpoint, adds `AllowDemoMcpPublicTds` from `AzureCloud` to TCP `3342`, derives the public FQDN, and stores it in azd.

## 7. Deploy schema, data, and SQL authorization

```powershell
./scripts/deploy-demo-database.ps1 `
  -Server "$($values.SQL_MI_PUBLIC_FQDN),3342" `
  -McpIdentityName $values.AZURE_MCP_IDENTITY_NAME `
  -McpIdentityObjectId $values.AZURE_MCP_IDENTITY_PRINCIPAL_ID
```

The scripts are idempotent and create only synthetic data, approved views/procedures, `mcp_reader`, and the MCP UAMI contained user.

## 8. Deploy SQL MCP Container App and project connection

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

## 9. Register and test the prompt agent

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

## 10. Open Foundry Playground

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

## 11. Cleanup

```powershell
./scripts/cleanup-demo.ps1 -ConfirmCleanup -DropDatabase
```

Cleanup deletes the demo RG, removes or drops the synthetic database, removes the temporary NSG rule, disables the SQL MI public endpoint, and stops SQL MI. It does not delete the existing private Foundry RG, VNet, private endpoints, or SQL MI.