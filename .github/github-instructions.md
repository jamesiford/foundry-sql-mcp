# GitHub Copilot Repository Instructions

## Repository purpose

Build a secure, code-first Azure AI Foundry reference solution where a Foundry agent can access a synthetic Azure SQL Managed Instance dataset through two paths:

1. Foundry IQ using an Azure SQL / Azure SQL Managed Instance knowledge source.
2. SQL MCP Server using Microsoft SQL MCP Server built on Data API builder.

The solution must provision infrastructure, seed synthetic data, configure least-privileged access, and document the full deployment and demo flow.

## Current implementation direction

- On `demo/public-evaluation`, follow `docs/demo-roadmap.md` and implement SQL MCP Server only. Do not add Foundry IQ, Search knowledge sources, knowledge bases, embedding models, or an IQ agent. Keep public demo infrastructure isolated from `main` and preserve the cleanup path.
- Phase 2 IaC is implemented and partially deployed in `centralus`. SQL MI, Foundry, the project/model, private dependencies, private endpoints, and the project capability host succeeded. The internal Container Apps environment failed on regional `AKSCapacityHeavyUsage` and requires an idempotent retry before Phase 2 is complete.
- Implement the private SQL MCP path first and complete it end to end.
- Provision the private Azure AI Search service required by Standard Agent Setup, but defer the Azure SQL knowledge source, indexer, retrieval index, Foundry IQ knowledge base, and IQ agent behind an opt-in profile.
- Use Microsoft Foundry Standard Agent Setup with BYO VNet for private MCP connectivity.
- Keep the SQL MI public data endpoint disabled by default.
- Preview APIs and SDKs are allowed when version-pinned, documented, and validated; preview status doesn't relax security requirements.
- Create two project-native prompt agents with `azure-ai-projects` 2.x, `AIProjectClient.agents.create_version`, and `PromptAgentDefinition`:
	- `transfer-agent-sql-mcp` for the private SQL MCP path.
	- `transfer-agent-foundry-iq` for the deferred Foundry IQ comparison path.
- Both agents must use the same model, baseline instructions, and evaluation set and must surface in the new Microsoft Foundry portal.
- Treat `README.md` as the normative portal-first customer runbook. Keep all instructions, supporting docs, RBAC matrices, SQL grants, phase status, and preview limitations aligned with it.

## Non-negotiable principles

- Use code-first automation wherever possible.
- Prefer Azure Developer CLI and Bicep for infrastructure.
- Prefer Python for agent scaffolding and data generation.
- Use managed identities and Microsoft Entra authentication wherever supported.
- Do not commit secrets, connection strings with credentials, tokens, certificates, API keys, or generated local environment files.
- Runtime identities must be least privileged.
- Do not grant runtime identities Owner, Contributor, db_owner, db_datareader, or db_datawriter.
- Agents must not generate unrestricted SQL.
- Agents should consume curated views, stored procedures, Foundry IQ, and SQL MCP tools.
- Keep implementation phased, testable, and clean.
- Assign human access to Entra groups at the narrowest scope: `Foundry Agent Consumer` for end users, `Foundry User` for project developers, `Foundry Project Manager` for designated leads/publishers, and PIM-eligible elevated roles for administrators.
- Foundry endpoint authorization does not provide per-user SQL row filtering. Document OBO/RLS, ACL-aware retrieval, or separate agents/knowledge bases before claiming user-specific data entitlements.

## Identity boundaries

- The Foundry project system-assigned managed identity accesses Standard Agent Setup dependencies and project connections.
- The shared project agent identity is a separate Entra agent identity used by unpublished agents when agent identity authentication is selected. Its blueprint is federated to the project identity; do not conflate the principals.
- Published agents receive distinct agent identities. Reapply only required downstream permissions because shared-project permissions do not transfer.
- The MCP user-assigned managed identity receives `AcrPull` and the custom `mcp_reader` SQL role only.
- The Search system-assigned managed identity receives the optional IQ ingestion permissions: SQL MI `Reader`, custom `agent_reader`, and model access only when embeddings or synthesis require it.

## Target architecture

Provision and configure:

- Azure resource group
- Azure AI Foundry resource / account
- Azure AI Foundry project
- Model deployment suitable for tool calling
- Foundry agent
- Azure SQL Managed Instance
- VNet and subnets required for SQL Managed Instance
- SQL database with synthetic data
- SQL views and stored procedures for agent access
- SQL custom database roles for least privilege
- User-assigned managed identity for SQL MCP Server
- Azure Container Apps environment
- Azure Container App for SQL MCP Server
- Application Insights and Log Analytics
- Foundry IQ knowledge source / knowledge base over approved SQL views where supported

## Preferred repo structure

```text
.
├── README.md
├── azure.yaml
├── .gitignore
├── .env.example
├── .github/
│   └── copilot-instructions.md
├── infra/
│   ├── main.bicep
│   ├── main.parameters.json
│   └── modules/
│       ├── foundry.bicep
│       ├── networking.bicep
│       ├── sql-mi.bicep
│       ├── identities.bicep
│       ├── container-apps.bicep
│       ├── monitoring.bicep
│       └── role-assignments.bicep
├── src/
│   ├── agent/
│   ├── data/
│   └── mcp-server/
├── docs/
│   ├── architecture.md
│   ├── security.md
│   ├── foundry-iq.md
│   ├── sql-mcp.md
│   └── decisions/
│       └── ADR-001-foundry-sql-agent-architecture.md
└── scripts/
```

## Implementation phases

### Phase 1: Scaffold

Create the repo structure, README, architecture docs, security docs, ADR folder, Bicep module placeholders, and scripts folder.

### Phase 2: Infrastructure

Implement networking, SQL MI, managed identities, monitoring, Container Apps, Foundry resource, Foundry project, and role assignments.

### Phase 3: Database and synthetic data

Create schema, tables, relationships, indexes, synthetic data generator, views, and stored procedures.

### Phase 4: SQL security

Create custom SQL roles and map managed identities to SQL users using Microsoft Entra authentication.

### Phase 5: SQL MCP Server

Configure Data API builder / SQL MCP Server to expose only approved views and stored procedures. Start read-only.

### Phase 6: SQL MCP Foundry prompt agent

Create and evaluate the versioned SQL MCP prompt agent with the private MCP tool connection.

### Phase 7: Foundry IQ comparison

Create or document the opt-in Azure SQL knowledge source, knowledge base, and versioned IQ prompt agent using approved SQL views.

### Phase 8: Tests and CI/CD

Add validation, smoke tests, secret scanning, Bicep validation, MCP exposure tests, and agent behavior tests.

## Database domain

Use synthetic wealth management / account transfer data.

Required tables:

- Client
- Household
- Advisor
- Account
- AssetTransfer
- TransferStatusHistory
- DocumentChecklist
- RiskAlert
- InteractionNote

Required views:

- vw_transfer_summary
- vw_client_account_overview
- vw_transfer_risk_dashboard
- vw_advisor_pipeline

Required stored procedures:

- usp_GetTransferSummaryByClient
- usp_GetOpenRiskAlerts
- usp_GetAdvisorPipeline

## SQL least privilege

Create custom database roles:

- agent_reader: SELECT only on approved views.
- agent_executor: EXECUTE only on approved stored procedures.
- mcp_reader: read-only MCP access to approved entities.

Example pattern:

```sql
CREATE USER [<managed-identity-name>] FROM EXTERNAL PROVIDER;
ALTER ROLE agent_reader ADD MEMBER [<managed-identity-name>];
ALTER ROLE agent_executor ADD MEMBER [<managed-identity-name>];
```

Do not grant runtime identities:

```sql
db_owner
db_datareader
db_datawriter
```

## SQL MCP Server requirements

- Use Microsoft SQL MCP Server / Data API builder.
- Containerize it.
- Deploy it to Azure Container Apps.
- Use managed identity / Microsoft Entra authentication where supported.
- Expose only approved views and stored procedures.
- Include entity descriptions and field metadata.
- Disable write operations initially.
- Provide local testing with MCP Inspector or equivalent.

## Foundry IQ requirements

- Use approved SQL views as knowledge source inputs where possible.
- Use explicit schema mapping.
- Use stable key columns.
- Include fields useful for retrieval, filtering, and citations.
- Automate setup where supported by stable APIs.
- If portal steps are required, document exact steps in docs/foundry-iq.md.
- Use Search Service REST API `2026-05-01-preview` only while it remains the validated contract; verify API availability and retest before customer automation.
- Treat the restricted SQL MI public endpoint profile as evaluation-only. Shared private link remains rejected while it requires SQL credentials.

## Documentation requirements

- Keep the README comprehensive enough to stand up the architecture through Azure portal and Microsoft Foundry portal.
- Document every role with principal, role/permission, scope, timing, purpose, and explicit exclusions.
- Separate Azure control-plane RBAC, Azure data-plane RBAC, SQL database authorization, DAB entity permissions, network reachability, and end-user agent invocation.
- Mark deferred components and phase-specific validation gates clearly; never imply that planned agents or data paths are operational.
- Link current Microsoft Learn sources for preview and fast-moving portal behavior.

## Agent behavior

Both prompt agents should avoid inventing data, state clearly when supporting data is unavailable, and deny writes. The IQ agent should use its knowledge base for broad semantic retrieval and cite evidence. The SQL MCP agent should use only allowlisted tools for structured operations and summarize tool output.

## Definition of done

The repo is complete when:

- azd up provisions the core infrastructure or clearly documents preview-only manual steps.
- SQL MI database is created and seeded with synthetic data.
- Least-privileged access is enforced.
- SQL MCP Server works.
- Foundry IQ works or is documented with exact setup steps.
- Agent can answer through both paths.
- CI/CD validates infrastructure, code, tests, and secret hygiene.
