# ADR-001: Foundry SQL Agent Architecture

- **Status:** Accepted
- **Date:** 2026-07-13
- **Scope:** Reference architecture and phased implementation boundaries

## Context

The repository needs to demonstrate how a Microsoft Foundry agent can use enterprise-style relational data in Azure SQL Managed Instance without receiving database credentials or unrestricted SQL capability.

Two request shapes must be supported:

1. Semantic questions that require retrieval, synthesis, and evidence.
2. Structured questions that require deterministic filters, lookups, aggregates, or parameterized reports.

A single generic SQL tool would collapse these concerns, increase prompt-injection risk, and make least-privilege authorization difficult to prove.

## Decision

Build a code-first, phased reference solution with:

- Azure Developer CLI for orchestration.
- Bicep modules for infrastructure.
- Azure SQL Managed Instance for the relational store.
- Synthetic wealth-management account-transfer data only.
- Curated SQL views and stored procedures as the complete agent-facing data contract.
- Foundry IQ with an Azure SQL or SQL MI knowledge source for semantic retrieval.
- Microsoft SQL MCP Server built on Data API builder for deterministic structured access.
- Managed identities and Microsoft Entra authentication wherever supported.
- Separate deployment, Foundry, agent, ingestion, and MCP identities.
- Custom SQL roles with named-object grants instead of broad built-in roles.
- Read-only behavior for both data paths.

The original routing concept has been refined into two comparable prompt agents by [ADR-002](ADR-002-two-prompt-agents-and-connectivity.md). The Foundry IQ agent handles narrative and discovery questions; the SQL MCP agent handles exact lookups, filters, counts, groupings, statuses, and approved reports. Neither receives a tool that accepts arbitrary SQL.

## Data access decision

Foundry IQ may retrieve from these approved views:

- `vw_transfer_summary`
- `vw_client_account_overview`
- `vw_transfer_risk_dashboard`
- `vw_advisor_pipeline`

SQL MCP may expose those views plus:

- `usp_GetTransferSummaryByClient`
- `usp_GetOpenRiskAlerts`
- `usp_GetAdvisorPipeline`

Raw OLTP tables are not agent-facing. Database roles grant `SELECT` and `EXECUTE` on named objects only.

## Phase decision

Phase 1 established contracts and syntactically valid no-resource Bicep placeholders. Phase 2 subsequently implemented infrastructure and was partially deployed in Central US on 2026-07-13. SQL MI, Foundry, the project/model, private dependencies, private endpoints, and the project capability host succeeded; the internal Container Apps environment requires an idempotent retry after regional capacity failure. Each later phase must add its own security and behavior validation before the next layer is introduced.

## Alternatives considered

### Allow the model to generate SQL

Rejected. Query validation and database permissions would have to defend an unbounded language surface, and business operations would not have stable tool contracts.

### Use SQL MCP for every question

Rejected. Structured tools are appropriate for deterministic operations but are a poor substitute for semantic retrieval, narrative synthesis, and evidence-based discovery.

### Use Foundry IQ for every question

Rejected. Semantic retrieval does not guarantee deterministic aggregation, filtering, or exact operational reporting.

### Grant broad read access to simplify setup

Rejected. `db_datareader` exposes all current and future user tables and views, violating the reference solution's least-privilege goal.

## Consequences

Benefits:

- Data access is bounded by explicit SQL and tool contracts.
- Each retrieval path can be authorized, tested, observed, and diagnosed independently.
- Managed identity removes committed SQL credentials.
- The demo clearly illustrates when semantic retrieval and deterministic tools differ.

Costs and risks:

- SQL MI adds subnet, private DNS, deployment-time, and cost considerations.
- Foundry IQ support for SQL MI, private connectivity, and automation may vary by region and API version.
- Entra administration and contained-user creation require tenant-specific setup and controlled deployment permissions.
- Two data paths require separate freshness, authorization, and evaluation tests.

## Follow-up decisions

- ADR-002: Two prompt agents, SQL MCP hosting/networking, and the optional IQ connectivity profile (accepted)
- ADR-003: Foundry IQ indexing, key, citation, and freshness strategy
- ADR-004: SQL write-access policy, if write support is ever proposed
- ADR-005: Private networking, DNS, and Foundry-to-SQL connectivity
