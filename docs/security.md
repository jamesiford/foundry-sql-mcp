# Security Model

## Security objectives

- Eliminate stored SQL credentials by using managed identity and Microsoft Entra authentication.
- Separate deployment authority from runtime authority.
- Prevent unrestricted SQL generation and raw-table exposure.
- Constrain each data path to an explicit allowlist.
- Keep ingress, database connectivity, and observability private or authenticated.
- Use synthetic data exclusively.

Phase 2 has created the project and MCP managed identities and the Standard Agent Setup dependency role assignments. SQL contained users, custom database roles, Search ingestion permissions, end-user assignments, and published agent identities remain deferred to their designated phases.

Preview features are permitted, but preview status does not override these controls. Each preview API or SDK must be pinned and tested. A preview feature that requires a SQL password is rejected even when the preview itself is acceptable.

## Identity matrix

| Identity | Lifecycle | Authenticates to | Allowed responsibility | Explicitly excluded |
|---|---|---|---|---|
| Developer or CI deployment identity | Deployment only | Azure Resource Manager | Run validated azd/Bicep deployments and create approved role assignments | Application runtime, SQL query execution |
| Foundry project managed identity | Platform/runtime | Foundry dependencies and future knowledge-source connection where supported | Project-scoped platform operations and approved data-source access | Direct broad SQL access, subscription management |
| Shared project agent identity | Development runtime | Private MCP endpoint or deferred Foundry IQ knowledge base when Agentic Identity authentication is selected | Invoke only registered and approved tools shared by unpublished agents | SQL credentials, arbitrary SQL, deployment operations |
| Published agent identity | Published runtime | Only the tools configured for one published agent application | Independently auditable, right-sized tool access | Inheriting shared-project permissions automatically |
| Foundry IQ ingestion identity | Indexing/retrieval | Approved SQL knowledge source | Read only the views selected for the knowledge source | Raw tables, stored procedure execution, writes |
| MCP server user-assigned managed identity | Runtime | Azure Container Registry and SQL MI | Pull the approved image and access allowlisted MCP entities through custom SQL roles | Broad Azure roles, raw tables, DDL/DML |
| Human SQL administrator | Break-glass/setup | SQL MI through Entra | Create database users and narrowly scoped roles during controlled setup | Application runtime use, shared credentials |

The project managed identity and shared project agent identity are separate principals. Foundry federates the shared identity's blueprint to the project identity, but downstream roles belong to the principal selected by the connection. Publishing creates another distinct identity, and downstream assignments don't transfer. The final relationship between the retrieval identity and the Search ingestion identity must be validated before Phase 7 automation.

## Human access matrix

| Persona | Minimum role | Scope | Constraint |
|---|---|---|---|
| Platform administrator | `Contributor` plus `Role Based Access Control Administrator`, or temporary `Owner` | Deployment resource group; subscription only when required | PIM-eligible; no runtime use |
| Foundry account/model administrator | `Foundry Account Owner` | Foundry resource | PIM-eligible |
| Lead developer/publisher | `Foundry Project Manager` | Foundry resource or project according to task | Limited to designated leads |
| Agent developer | `Foundry User` | One project | No Azure resource administration |
| End user/application | `Foundry Agent Consumer` | Individual agent where possible | Endpoint invocation only |
| IQ builder | `Search Service Contributor` and `Search Index Data Contributor` | IQ Search service | Time-bound build access |
| Auditor | `Reader` and `Log Analytics Reader` as needed | Resource group and workspace | No invocation or mutation |

## Azure permission matrix

| Principal | Scope | Planned permission | Purpose | Constraint |
|---|---|---|---|---|
| Deployment identity | Deployment resource group and required subscription operations | Custom or built-in deployment permissions selected during Phase 2 | Provision resources and approved assignments | No runtime use; avoid subscription-wide role grants where resource-group scope works |
| Foundry project identity | Specific connected resource | Narrow data-plane role required by the validated Foundry connection | Use the configured project dependency | No `Owner` or `Contributor` |
| Shared or published agent identity | Specific MCP endpoint or Search service | Invoke-only or `Search Index Data Reader` as required | Call registered tools | No SQL or ARM role unless a demonstrated requirement exists |
| MCP managed identity | Specific container registry | `AcrPull` | Pull the MCP image | No registry push or administrative role |
| MCP managed identity | SQL database | SQL contained user and custom database role, not Azure RBAC | Read approved SQL entities | No server administrator or broad database role |
| Search managed identity | SQL database, optional IQ profile only | SQL contained user with named-view `SELECT` | Index approved IQ views | No raw-table access, stored procedure execution, or writes |
| Monitoring writers | Specific telemetry resource | Telemetry ingestion configuration supplied by the platform | Emit traces and metrics | No Log Analytics query role unless operationally required |

Current Foundry role choices are `Foundry Agent Consumer` for invocation, `Foundry User` for project development, `Foundry Project Manager` for designated leads/publishing, and `Foundry Account Owner` for account/model administration. Role assignments must be justified individually and scoped as narrowly as the platform supports.

The Phase 2 Bicep currently grants the project identity Storage Blob Data Contributor, ABAC-constrained Storage Blob Data Owner, Cosmos DB Operator, Cosmos DB Built-in Data Contributor, Search Index Data Contributor, and Search Service Contributor. July 2026 Standard Setup guidance also calls for `Storage Account Contributor` and `Foundry User` on the project identity and recommends generated-container/database scopes. Verify those requirements and narrow bootstrap scopes after generated resources exist.

## SQL permission matrix

| Database principal or role | Permission | Securable | Assigned identity |
|---|---|---|---|
| `agent_reader` | `SELECT` | Approved Foundry IQ views only | Foundry IQ ingestion identity, if required by the supported connection model |
| `agent_executor` | `EXECUTE` | Approved stored procedures only | Future agent-side database principal only if an architecture change explicitly requires it |
| `mcp_reader` | `SELECT` and approved procedure `EXECUTE` | Data API builder allowlist only | MCP server managed identity |

Runtime identities must never receive:

```text
db_owner
db_datareader
db_datawriter
Owner
Contributor
```

`db_datareader` is intentionally excluded because it grants access to every user table and view. Grants must target named views and stored procedures.

## Planned SQL authorization pattern

Phase 4 will create contained users from Microsoft Entra identities and add them to custom roles. No SQL login or password is permitted.

```sql
CREATE USER [<managed-identity-name>] FROM EXTERNAL PROVIDER;
ALTER ROLE [mcp_reader] ADD MEMBER [<managed-identity-name>];
```

The placeholder is tenant-specific and must be resolved from the deployed managed identity rather than hard-coded.

## Data-path controls

| Control | Foundry IQ | SQL MCP |
|---|---|---|
| Source allowlist | Approved views | Approved views and stored procedures |
| Authentication | Managed identity/Entra where supported | MCP managed identity/Entra |
| Write access | None | None |
| Raw table access | Denied | Denied |
| Result behavior | Grounded answer with evidence or citation | Structured tool result summarized by the agent |
| Failure behavior | State that evidence is unavailable | Return a bounded tool error; do not fall back to generated SQL |

## End-user authorization boundary

Agent endpoint RBAC and data authorization are separate. `Foundry Agent Consumer` lets a principal invoke an endpoint; it doesn't trim SQL rows. In the default application-identity design, all authorized callers can receive data allowed to the MCP or Search workload identity. Production user-specific entitlements require OAuth OBO with SQL row-level security, ACL-aware retrieval with per-request user context, or separate agents and knowledge bases for entitlement groups.

## Network controls

- Place SQL MI in its required delegated subnet.
- Use Microsoft Foundry Standard Agent Setup with private networking; Basic Agent Setup doesn't support private MCP endpoints.
- Integrate an internal-only Container Apps environment with a dedicated MCP/infrastructure subnet delegated to `Microsoft.App/environments`.
- Resolve SQL MI through private DNS and restrict network security rules to required flows.
- Keep SQL MI public data endpoint disabled in the default deployment.
- Route MCP-to-SQL traffic through the VNet-local SQL MI endpoint on TCP `1433`.
- Authenticate the MCP endpoint and avoid anonymous public ingress.
- Restrict outbound access from the MCP workload to required Azure control-plane, identity, registry, telemetry, and SQL endpoints.

### Optional Foundry IQ public profile

The deferred IQ profile may enable the SQL MI public endpoint for customer evaluation because Search shared private link to SQL MI currently requires SQL credentials. This exception does not change the MCP route.

| Control | Required setting |
|---|---|
| Feature flag | Disabled by default |
| Search-to-SQL hostname | SQL MI public FQDN only |
| Port | TCP `3342` only |
| Network source | Search service IP plus required `AzureCognitiveSearch` ranges; never `Internet` or `AzureCloud` |
| Authentication | Search managed identity and Microsoft Entra |
| SQL authorization | `SELECT` on approved IQ views only |
| Encryption | TLS required |
| MCP hostname | SQL MI VNet-local FQDN, unchanged |
| MCP port | TCP `1433`, unchanged |

The `AzureCognitiveSearch` service tag covers Search indexer execution infrastructure and isn't scoped to one Search resource. Network filtering must therefore be combined with Entra authentication and named-view SQL grants. The public profile is restricted public access, not private isolation.

## Secrets and configuration

- Commit `.env.example` with names and non-secret defaults only.
- Ignore `.env` and environment-specific variants.
- Never store tokens, passwords, certificates, API keys, or credential-bearing connection strings in source control, Bicep parameters, azd configuration, or container environment variables.
- Treat Application Insights connection strings as configuration, but still avoid logging them unnecessarily.
- If a future dependency cannot use managed identity, document the exception and use an approved secret store; do not silently introduce a secret.

## Required security validation

- Scan tracked files for credentials and private keys.
- Review the generated ARM template and role assignments before deployment.
- Prove that runtime identities lack broad Azure and SQL roles.
- Prove that raw tables and write operations are absent from Data API builder metadata.
- Prove that Foundry IQ citations resolve only to approved synthetic records.
- Prove that the MCP container resolves and connects only to the VNet-local SQL MI endpoint.
- When the IQ public profile is enabled, prove that TCP `3342` rejects non-Search sources and that the MCP route remains on TCP `1433`.
- Test prompt-injection attempts that ask for raw SQL, hidden schema, writes, or unavailable records.
- Confirm logs contain no prompts or record payloads beyond the approved telemetry policy.
