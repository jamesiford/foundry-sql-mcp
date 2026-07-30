# GitHub Copilot Repository Instructions

## Purpose

Build a secure, code-first Microsoft Foundry reference solution in phases. Two comparable Foundry v2 prompt agents will access synthetic Azure SQL Managed Instance data through:

1. Foundry IQ over approved Azure SQL knowledge-source views.
2. Microsoft SQL MCP Server, built on Data API builder, over approved views and stored procedures.

## Current phase

On branch `demo/public-evaluation`, implement only the approved public SQL MCP demonstration in `docs/demo-roadmap.md`. Foundry IQ, Azure AI Search knowledge sources, knowledge bases, embedding models, and an IQ agent are out of scope. The demo uses disposable Entra-only Azure SQL Database; SQL MI remains the documented customer backend. Public Foundry, MCP, ACR, SQL Database, and monitoring are demo-only and must not be merged into `main` as production defaults.

Phase 1 is complete. Phase 2 infrastructure is implemented and partially deployed in `centralus` under azd environment `foundry-sql-mcp-dev-centralus`. The last validated deployment created SQL MI, networking, managed identities, monitoring, private Standard Agent Setup dependencies, the Foundry resource/project, `gpt-5.4-mini`, project connections, private endpoints, and the project capability host. SQL MI reached `Ready` and the capability host reached `Succeeded`. The internal Container Apps environment failed with regional `AKSCapacityHeavyUsage` and requires an idempotent retry. Do not describe Phase 2 as fully deployed until that retry and post-deployment checks pass.

Phase 2 may provision the private Azure AI Search service required by Standard Agent Setup. Do not implement SQL schemas, synthetic data, database roles, Data API builder configuration, SQL MCP Server logic, prompt-agent registration, Azure SQL knowledge sources, Search indexers/retrieval indexes, or Foundry IQ knowledge bases until their designated phases. The private SQL MCP path is primary; the Foundry IQ data plane is deferred and opt-in.

## Engineering rules

- Use Azure Developer CLI and Bicep for infrastructure orchestration.
- Prefer Python for later agent and data tooling.
- Keep changes phased, testable, and narrowly scoped.
- Keep all Bicep modules syntactically valid and idempotent.
- Use `TODO` comments only for tenant-specific values, preview APIs, or steps requiring manual validation.
- Validate Bicep after infrastructure edits.
- Preview features are allowed when the exact API/SDK version, limitation, fallback, and validation are documented.

## Security rules

- Never commit secrets, tokens, certificates, API keys, SQL passwords, credential-bearing connection strings, or generated local environment files.
- Use managed identities and Microsoft Entra authentication wherever supported.
- Keep deployment, Foundry, agent, and MCP runtime identities separate.
- Grant runtime identities only the permissions required at the narrowest practical scope.
- Do not grant runtime identities `Owner`, `Contributor`, `db_owner`, `db_datareader`, or `db_datawriter`.
- Do not allow an agent to issue unrestricted SQL.
- Expose curated views and stored procedures, not raw tables.
- Keep the SQL MCP path read-only until an explicit write-mode decision is documented and tested.
- Use synthetic data only.
- Keep the SQL MI public data endpoint disabled in the default deployment.
- Do not use Search shared private link to SQL MI while it requires SQL username/password authentication.
- Give end users `Foundry Agent Consumer` at individual-agent scope where possible. Do not give end users `Foundry User`, `Contributor`, or `Owner`.
- Do not claim that Foundry endpoint RBAC provides per-user SQL row filtering. The default application-identity paths expose the data authorized to the MCP or Search identity; user-specific entitlements require OBO/RLS, ACL-aware retrieval, or separate agents/knowledge bases.

## Identity model

Keep these principals distinct:

- The Foundry project system-assigned managed identity accesses Standard Setup dependencies and project connections.
- The shared project agent identity is a separate Entra agent identity used by unpublished agents when an MCP connection selects agent identity authentication. Its blueprint is federated to the project identity, but it is not the same principal.
- A published agent receives its own distinct agent identity. Reassign only that identity's required downstream roles; shared-project assignments do not transfer.
- The MCP user-assigned managed identity authenticates from Data API builder to SQL MI and receives only `AcrPull` plus the `mcp_reader` SQL role.
- The Search system-assigned managed identity performs optional IQ ingestion and receives only SQL MI `Reader`, the `agent_reader` SQL role, and model access required for embeddings/synthesis.

The portal-first setup, role matrices, SQL grants, phase gates, and current limitations in `README.md` are normative documentation. Keep supporting docs aligned with it.

## Agent implementation decision

Later agent work will create two project-native Foundry v2 prompt agents with `azure-ai-projects` 2.x, `AIProjectClient.agents.create_version`, and `PromptAgentDefinition`:

- `transfer-agent-sql-mcp` uses the private SQL MCP endpoint.
- `transfer-agent-foundry-iq` uses the deferred Foundry IQ knowledge base MCP endpoint.

Use the same model deployment, baseline instructions, and evaluation set for both. Agent versions must be registered in the Foundry project and visible in the new Microsoft Foundry portal. Do not replace these prompt agents with hosted agents unless a later ADR changes the decision.

## Agent-facing data contract

The Foundry IQ prompt agent should serve semantic retrieval and grounded narrative answers. The SQL MCP prompt agent should serve deterministic lookups, filters, aggregations, status checks, and operational reporting. Both agents must avoid invented data and state when supporting data is unavailable; the IQ agent must cite evidence and the MCP agent must summarize tool results.

## Planned SQL objects

Approved views:

- `vw_transfer_summary`
- `vw_client_account_overview`
- `vw_transfer_risk_dashboard`
- `vw_advisor_pipeline`

Approved stored procedures:

- `usp_GetTransferSummaryByClient`
- `usp_GetOpenRiskAlerts`
- `usp_GetAdvisorPipeline`

Planned custom roles:

- `agent_reader`: `SELECT` on approved views only.
- `agent_executor`: `EXECUTE` on approved stored procedures only.
- `mcp_reader`: read-only access to approved MCP entities only.

## Validation expectations

- Compile `infra/main.bicep` with no errors.
- Parse JSON and YAML configuration with appropriate tooling.
- Run syntax checks for PowerShell and shell scripts.
- Scan for accidentally committed credentials before deployment.
- Do not claim a component works until its phase-specific validation exists and passes.
