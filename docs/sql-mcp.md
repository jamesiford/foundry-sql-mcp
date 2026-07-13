# SQL MCP Server

## Status and implementation gate

The structured data path will use Microsoft SQL MCP Server built on Data API builder 2.x and hosted in Azure Container Apps. Phase 2 has provisioned the dedicated MCP managed identity and subnet, but the internal Container Apps environment requires a capacity retry. No MCP process, container image, Data API builder configuration, SQL connection, database user, or agent tool registration exists yet.

The server will expose bounded, descriptive tools for deterministic lookups, filters, aggregates, statuses, and reports. It will not expose a general SQL execution tool.

This is the primary implementation path. Foundry IQ is deferred until this path is deployed, authorized, and evaluated end to end.

## Approved entity allowlist

| SQL object | MCP purpose | Initial operations |
|---|---|---|
| `vw_transfer_summary` | Transfer lookup and status filtering | Read only |
| `vw_client_account_overview` | Client/account lookup | Read only |
| `vw_transfer_risk_dashboard` | Open-risk filtering and reporting | Read only |
| `vw_advisor_pipeline` | Advisor pipeline grouping and totals | Read only |
| `usp_GetTransferSummaryByClient` | Parameterized client transfer summary | Execute only |
| `usp_GetOpenRiskAlerts` | Parameterized open-risk report | Execute only |
| `usp_GetAdvisorPipeline` | Parameterized advisor pipeline report | Execute only |

Raw tables, arbitrary queries, schema mutation, inserts, updates, deletes, and administrative operations are denied.

## Authentication flow

1. The Foundry agent obtains an Entra token for the MCP API audience using the identity selected by its MCP project connection.
2. Data API builder validates the token issuer and audience. An Entra application role or gateway policy should restrict callers when tenant-wide authenticated access is too broad.
3. The Container App runs with a dedicated user-assigned managed identity.
4. Data API builder obtains an Entra token for Azure SQL using that UAMI's client ID.
5. SQL MI maps the UAMI to a contained database user.
6. The user belongs only to `mcp_reader`, whose grants target allowlisted objects.

The project managed identity, shared project agent identity, and published agent identity are separate principals. A connection configured as Project Managed Identity uses the project principal. Agentic Identity authentication uses the shared identity for unpublished agents or the distinct published identity after publication. Downstream permissions don't transfer automatically.

No SQL credential or credential-bearing connection string is stored in source, azd values, Bicep parameters, or container secrets.

## Data API builder requirements

- Pin and validate a DAB 2.x image.
- Configure `EntraId` inbound authentication with the MCP API Application ID URI as JWT audience and the tenant v2 issuer.
- Use an allowlist configuration; do not rely on denylisting unwanted tables.
- Give every entity and field an accurate description for tool discovery.
- Use stable, domain-specific operation names.
- Define required parameter types and bounded result shapes.
- Disable create, update, delete, and unrestricted execute operations.
- Keep introspection and metadata exposure to the minimum required by MCP.
- Configure health/readiness endpoints without revealing dependency details.
- Emit structured telemetry without logging tokens, prompts, or full record payloads.
- Treat DAB entity roles as an additional policy layer; they can narrow but never expand the SQL permissions of `mcp_reader`.

## Hosting requirements

- Build a pinned, reproducible container image.
- Run in Azure Container Apps with the dedicated MCP identity.
- Pull the image using `AcrPull` at registry scope.
- Use Microsoft Foundry Standard Agent Setup with BYO VNet; Basic Agent Setup doesn't support private MCP endpoints.
- Run the Container Apps environment with internal-only ingress on a dedicated subnet delegated to `Microsoft.App/environments`.
- Use the SQL MI VNet-local endpoint on TCP `1433` and authenticated private ingress for MCP.
- Keep `publicDataEndpointEnabled` disabled in the default deployment.
- Configure minimum and maximum replicas deliberately; do not infer production scale from this demo.
- Fail startup when identity or database authorization is invalid rather than falling back to SQL authentication.

## Foundry prompt agent

The SQL MCP agent will be registered in the Foundry project using `azure-ai-projects` 2.x:

```python
mcp_tool = MCPTool(
	server_label="sql-mcp",
	server_url=sql_mcp_endpoint,
	allowed_tools=approved_tool_names,
	require_approval="never",
	project_connection_id=sql_mcp_connection_name,
)

agent = project_client.agents.create_version(
	agent_name="transfer-agent-sql-mcp",
	definition=PromptAgentDefinition(
		model=model_deployment_name,
		instructions=shared_baseline_instructions,
		tools=[mcp_tool],
	),
)
```

The created version is a project-native prompt agent visible in the new Microsoft Foundry portal and Playground. It is not a hosted-agent container; only the MCP server runs in Container Apps.

`require_approval="never"` is acceptable only while every allowed tool is read-only and individually allowlisted. Any future write tool requires a separate agent version, explicit approval policy, SQL role, ADR, and tests.

End users receive `Foundry Agent Consumer` at individual-agent scope where possible. This controls endpoint invocation but does not provide per-user SQL row filtering because MCP uses a workload identity by default. User-specific access requires an approved OBO/RLS or equivalent downstream policy design.

## Local development

A later phase will add a Data API builder configuration and commands for MCP Inspector or an equivalent client. Local authentication should use the developer's Entra identity or a documented test identity. Local SQL passwords are not an accepted fallback.

## Acceptance tests

Positive prompts:

```text
Show open transfers grouped by advisor.
```

```text
List high-risk open transfers with missing documents.
```

```text
Return the transfer summary for Contoso Demo Client 001.
```

Negative tests:

- Enumerating raw tables returns no tools or entities.
- Insert, update, delete, and DDL requests are rejected.
- A request for arbitrary SQL is rejected rather than translated.
- The MCP identity cannot select from a raw table through a direct SQL test.
- Unknown client identifiers return an empty bounded result, not invented records.
- Tool errors remain errors and do not trigger an unsafe fallback path.
- The Foundry runtime reaches MCP through the private Standard Agent Setup network.
- The MCP container connects to the SQL MI VNet-local endpoint on TCP `1433` and never to the `.public.` FQDN.

## Write-mode policy

Write support is outside the accepted architecture. Enabling it requires a new ADR, separate tools and permissions, explicit user confirmation semantics, audit coverage, and destructive-operation tests.
