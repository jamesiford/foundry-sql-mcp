# Foundry IQ

## Status and implementation gate

Foundry IQ is the future semantic retrieval path. Phase 2 has provisioned the private Azure AI Search service required by Standard Agent Setup and the shared model deployment, but it has not created an Azure SQL knowledge source, generated index/indexer/skillset, knowledge base, IQ project connection, or IQ prompt agent. This document defines the allowlist and acceptance criteria for Phase 7.

Foundry IQ is deferred until the private SQL MCP path works end to end. Phase 2 provisions a private Azure AI Search service because Microsoft Foundry Standard Agent Setup requires it for vector-store state. It does not create the Azure SQL knowledge source, indexer, retrieval index, knowledge base, IQ project connection, or IQ prompt agent.

Use Foundry IQ for narrative questions, theme discovery, and summaries that benefit from semantic retrieval. Use SQL MCP for exact lookups, filters, grouping, counts, and status reporting.

## Approved source views

Only these SQL views are candidates for the Azure SQL or Azure SQL Managed Instance knowledge source:

| View | Retrieval purpose | Required source characteristics |
|---|---|---|
| `vw_transfer_summary` | Transfer narrative and lifecycle status | Stable transfer key, status, dates, parties, summary text |
| `vw_client_account_overview` | Client and account context | Stable client/account keys, descriptive fields, account type |
| `vw_transfer_risk_dashboard` | Risk themes and supporting alerts | Stable alert/transfer keys, severity, reason, status, dates |
| `vw_advisor_pipeline` | Advisor pipeline narrative | Stable advisor and transfer keys, stage, age, aggregate context |

Raw tables are not knowledge-source inputs.

## Schema requirements

- Map every source column explicitly.
- Provide a stable, unique, non-null, single-column key that the indexed SQL connector can discover.
- Separate searchable narrative fields from filterable and sortable fields.
- Include source identifiers and display labels needed for evidence and citations.
- Include timestamps and status fields needed to explain freshness.
- Exclude internal-only fields, operational metadata, and unnecessary personal data.
- Keep each view backward compatible once used by a knowledge source.
- Provide a `rowversion` or equivalent high-water-mark column for view change detection and a soft-delete marker when deletions must propagate.

The `indexedSql` knowledge-source contract accepts one table or view per knowledge source and treats each row as one logical document. Ordinary views can lack discoverable primary-key metadata. Validate key discovery; if it fails, use a purpose-built ingestion table or supported indexed-view pattern rather than broadening permissions.

The exact column mapping will be finalized after Phase 3 defines the synthetic schema. It must be reviewed before indexing.

## Identity and connectivity

- Use the Azure AI Search managed identity for SQL indexing when the public test profile is enabled.
- Grant that identity `SELECT` only on the approved views through `agent_reader` or an equally narrow role.
- Do not use SQL usernames or passwords.
- Keep the SQL MI public data endpoint disabled in the default deployment.
- If the public test profile is enabled, use the SQL MI public FQDN on TCP `3342`, TLS, Entra authentication, and an NSG restricted to the Search service IP plus required `AzureCognitiveSearch` execution ranges.
- Never configure the SQL MCP server with the public SQL MI FQDN.
- Assign the Search managed identity `Reader` on SQL MI for the managed-identity indexer flow and `Cognitive Services User` on the model-hosting Foundry resource only when embeddings or synthesis require it.

## Connectivity limitations

| Option | Current behavior | Decision |
|---|---|---|
| Shared private link from Search to SQL MI | Preview `managedInstance` group is available, but managed identity isn't currently supported and the documented connection requires a SQL username/password | Reject while credentials are required |
| Restricted SQL MI public endpoint | Supports the Search indexer pattern and managed-identity SQL authorization | Allow only in an opt-in customer test profile |
| Separate curated staging source | Can retain private SQL MI while indexing a copied projection | Keep as fallback if public exposure is unacceptable |

The blocker on shared private link is authentication, not preview status. Preview features are acceptable in this repository when they preserve the security rules.

The optional public profile is evaluation-only. The `AzureCognitiveSearch` service tag is regional and not resource-scoped, so network reachability is broader than one Search resource. Entra authentication and the named-view `agent_reader` role remain the authorization boundary. Use a curated private staging source for production if that trade-off is unacceptable.

## Knowledge-source contract

- Use Search Service REST API `2026-05-01-preview` only while it remains the validated contract; verify current API availability before automation.
- Create one `indexedSql` knowledge source per approved view.
- Use managed identity and a credential-free SQL MI connection string containing the database and SQL MI ARM resource ID.
- Use `contentExtractionMode: minimal`.
- Add `embeddingColumns` only after the embedding deployment and Search-to-model role are ready.
- Review the generated data source, index, indexer, and optional skillset; avoid unsupported manual edits.
- Record and expose ingestion freshness because indexing is scheduled, not real time.

## Foundry prompt-agent connection

The IQ comparison agent is a versioned Foundry v2 prompt agent. Foundry IQ exposes the knowledge base through an MCP endpoint:

```text
{search-service-endpoint}/knowledgebases/{knowledge-base-name}/mcp?api-version=2026-05-01-preview
```

The Foundry project will contain a `RemoteTool` connection using `ProjectManagedIdentity` authentication and audience `https://search.azure.com/` while that remains the validated knowledge-base connection pattern. The agent's `MCPTool` configuration will set:

- `allowed_tools = ["knowledge_base_retrieve"]`
- `require_approval = "never"`
- `project_connection_id` to the IQ project connection

The actual retrieval identity needs `Search Index Data Reader` on the IQ Search service. With the current Project Managed Identity connection, that is the project identity. If the connection changes to Agentic Identity or the agent is published, assign the shared or distinct published agent identity instead. The project identity already has contributor roles on the shared Standard Setup Search service, so deploy a separate IQ Search service when strict reader-only retrieval separation is required.

The agent instructions must require retrieval, citations, and an explicit "I don't know" response when evidence is absent. End-user `Foundry Agent Consumer` access does not automatically filter indexed SQL documents per user; user-specific entitlements require ACL metadata and a client/runtime path that passes user authorization or separate entitlement-scoped knowledge bases.

## Automation boundary

Phase 7 should automate knowledge-source and knowledge-base creation through the current supported SDK or REST API. Preview APIs are permitted. Record:

1. The exact API version or portal blade.
2. Every field and identity selected.
3. The approved SQL view and key mapping.
4. Network and role prerequisites.
5. A repeatable post-configuration validation.

Manual configuration must remain isolated to this document and must not require a committed secret.

## Acceptance tests

Prompts:

```text
Summarize the current transfer pipeline and cite the records supporting each major risk theme.
```

```text
Which synthetic clients have delayed asset transfers, and what retrieved evidence explains the delay?
```

```text
What missing document types recur across open transfers?
```

Expected behavior:

- Every material claim is grounded in retrieved content.
- Citations identify the source view record or stable source key.
- Filters do not return records outside the approved synthetic dataset.
- Unsupported questions produce a clear data-unavailable response.
- The agent does not switch to generated SQL when retrieval is insufficient.

## Implementation gate

Do not start Foundry IQ configuration until the SQL MCP path is operational and the SQL views, stable keys, least-privilege Search database role, opt-in network profile, and current service APIs have all been validated.
