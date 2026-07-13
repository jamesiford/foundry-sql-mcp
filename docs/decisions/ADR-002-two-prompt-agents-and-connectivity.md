# ADR-002: Two Prompt Agents and Data-Path Connectivity

- **Status:** Accepted
- **Date:** 2026-07-13
- **Scope:** Agent registration, comparison design, preview posture, and SQL MI connectivity

## Context

The reference architecture originally described one agent that would route between Foundry IQ and SQL MCP. That design makes it harder to isolate the behavior, quality, latency, security, and operational cost of each data path.

The primary long-term path is Microsoft SQL MCP Server because it provides explicit, deterministic tools over approved views and stored procedures. Foundry IQ remains useful as a lower-infrastructure comparison for customers that want semantic retrieval over an Azure SQL knowledge source.

Private connectivity has different constraints for each path:

- Foundry Agent Service can reach a private MCP endpoint only with Standard Agent Setup and private networking.
- A VNet-integrated, internal Azure Container Apps environment can reach SQL MI through its VNet-local endpoint.
- Azure AI Search shared private link support for SQL MI is available in preview, but the documented private path currently requires a SQL username/password because managed identity isn't supported.
- A Search indexer can instead reach the SQL MI public endpoint with Microsoft Entra authentication, subject to TCP `3342` and NSG restrictions.

Preview features are acceptable for this non-production reference, but committed SQL credentials are not.

## Decision

Create two similar, project-native Microsoft Foundry prompt agents:

| Agent | Tool | Role |
|---|---|---|
| `transfer-agent-sql-mcp` | Private SQL MCP Server | Primary deterministic path |
| `transfer-agent-foundry-iq` | Foundry IQ knowledge base MCP endpoint | Deferred semantic comparison path |

Both agents will use:

- The same Foundry project.
- The same tool-calling model deployment.
- The same baseline instructions and domain terminology.
- The same synthetic evaluation records and question set.
- The same missing-data and anti-fabrication requirements.

The only intentional differences are the tool, tool-specific instructions, and citation requirements.

## Prompt-agent registration

Use `azure-ai-projects` 2.x and the Foundry v2 project API:

```python
agent = project_client.agents.create_version(
    agent_name=agent_name,
    definition=PromptAgentDefinition(
        model=model_deployment_name,
        instructions=instructions,
        tools=[mcp_tool],
    ),
)
```

This creates an immutable agent version in the Foundry project. Each agent is expected to appear in the new Microsoft Foundry portal agent experience and Playground. The agents are not hosted-agent containers.

Invoke registered agents through the project Responses API by agent reference. Pin the exact tested `azure-ai-projects` 2.x version when implementation begins.

## Identity and consumer-access decision

Treat the Foundry project managed identity, shared project agent identity, and each published agent identity as separate principals:

- Standard Setup dependencies and Project Managed Identity connections use the project managed identity.
- Unpublished agents use the shared project agent identity when a connection selects Agentic Identity authentication.
- Publishing creates a distinct agent identity; downstream role assignments don't transfer from the shared identity.

Grant end users `Foundry Agent Consumer` at individual-agent scope where possible. This authorizes endpoint invocation only. The default MCP and IQ workload identities establish a shared application data boundary and don't provide per-user SQL row filtering. Any user-specific entitlement design requires OBO with SQL row-level security, ACL-aware retrieval with per-request user context, or separate entitlement-scoped agents and knowledge bases.

## SQL MCP network decision

The default deployment will:

1. Use Microsoft Foundry Standard Agent Setup with BYO VNet.
2. Reserve a dedicated MCP subnet delegated to `Microsoft.App/environments`.
3. Deploy an internal-only Azure Container Apps environment.
4. Run Microsoft SQL MCP Server/Data API builder with a dedicated user-assigned managed identity.
5. Connect MCP to the SQL MI VNet-local FQDN on TCP `1433`.
6. Keep SQL MI `publicDataEndpointEnabled` set to `false`.
7. Expose only an explicit read-only MCP tool allowlist.

The SQL MCP agent uses `MCPTool` with the internal endpoint, an explicit `allowed_tools` list, and `require_approval="never"` only while all tools are read-only. Any write tool requires a separate decision, role, agent version, and approval policy.

## Foundry IQ decision

Provision the private Azure AI Search service required for Standard Agent Setup vector-store state. Defer the Azure SQL knowledge source, indexer, retrieval index, Foundry IQ knowledge base, IQ project connection, and IQ prompt agent until the SQL MCP path is operational. The presence of the platform Search service does not mean Foundry IQ is implemented.

The IQ agent will eventually connect to:

```text
{search-service-endpoint}/knowledgebases/{knowledge-base-name}/mcp?api-version=2026-05-01-preview
```

The Foundry project connection will use `RemoteTool`, `ProjectManagedIdentity`, and audience `https://search.azure.com/` while that remains the validated knowledge-base connection pattern. The agent will allow only `knowledge_base_retrieve`. If the connection moves to Agentic Identity, reassign `Search Index Data Reader` to the actual shared or published agent identity.

## Optional public IQ profile

Add a future opt-in feature flag that defaults to disabled. When enabled for customer testing:

1. Enable the SQL MI public data endpoint.
2. Configure the Search data source with the SQL MI public FQDN and TCP `3342`.
3. Permit only the Search service IP and required `AzureCognitiveSearch` execution ranges in the SQL MI subnet NSG.
4. Authenticate Search with its managed identity and Microsoft Entra.
5. Grant `SELECT` only on approved IQ views.
6. Require TLS.
7. Keep the MCP server on the private VNet-local FQDN and TCP `1433`.
8. Do not allow `Internet`, `AzureCloud`, or unrestricted source ranges.

This is restricted public access, not private isolation. The `AzureCognitiveSearch` service tag covers Search execution infrastructure and isn't scoped to one Search resource.

## Private IQ alternative

Azure AI Search supports a preview shared private link for `Microsoft.Sql/managedInstances` with group `managedInstance`. Do not use it while the documented connection requires a SQL username/password. Reevaluate when managed identity is supported.

The rejection is based on its credential requirement, not on preview status.

## Preview policy

Preview APIs and SDKs are permitted when:

- The exact version is pinned.
- The reason and limitation are documented.
- A focused validation proves the required behavior.
- A fallback, disable switch, or removal path exists.
- Least privilege, Entra authentication, and no-secret rules remain intact.

## Consequences

Benefits:

- The primary implementation remains private and credentialless.
- Customers can compare deterministic SQL tools with semantic retrieval using equivalent agents.
- Each agent has a clear security and evaluation boundary.
- The new Foundry portal provides a visible, testable agent version for each path.
- Preview capabilities can be used deliberately without weakening baseline controls.

Costs and risks:

- Standard Agent Setup requires more networking than Basic Agent Setup.
- Two agents require separate project connections, instructions, versions, and evaluations.
- The optional IQ public profile means SQL MI is not private-only while the profile is enabled.
- Search NSG source ranges aren't identity-specific, so SQL authorization remains essential.
- IQ data can lag SQL because Search indexers are scheduled rather than real-time.

## Revisit conditions

Revisit this decision when:

- Search shared private link to SQL MI supports managed identity.
- Foundry IQ's Azure SQL knowledge source networking or authentication model changes.
- A write-enabled MCP scenario is proposed.
- A single routing agent becomes a product requirement rather than a comparison concern.
