# Foundry Prompt Agent

Registration assets for the project-native Microsoft Foundry prompt agent that consumes the SQL MCP
Server. On this branch, `transfer-agent-sql-mcp-demo` is the only implemented agent; the Foundry IQ
comparison agent is out of scope.

> This code registers an **agent definition**. It is not the MCP server, and it is not required to
> stand the MCP server up. The Foundry portal can create an equivalent agent by hand — the script
> exists so the definition is versioned and reproducible.

## What is in this directory

| File | Purpose |
|---|---|
| `register_agent.py` | Creates or updates an immutable agent version via `AIProjectClient.agents.create_version` |
| `instructions.txt` | The agent's behavioural instructions |
| `smoke_test_agent.py` | Runs a question against the registered agent and checks a tool was actually invoked |
| `requirements.txt` | Pinned `azure-ai-projects` and `azure-identity` |

Run through the wrappers, which resolve environment values from `azd`:

```powershell
./scripts/register-demo-agent.ps1
./scripts/test-demo-agent.ps1
```

## The agent definition

**Model** — read from `AZURE_AI_MODEL_DEPLOYMENT_NAME`. Any current deployment works; the demo
uses `gpt-5.4-mini`.

**Connection** — references the Foundry RemoteTool connection by name (`sql-mcp-demo`), which
carries the MCP endpoint, the `api://<client-id>` audience, and project-managed-identity auth.

**Tool allowlist** — the agent may call only:

```
describe_entities · read_records · aggregate_records
get_transfer_summary_by_client · get_open_risk_alerts · get_advisor_pipeline
```

Custom tool names are **snake_case** derived from the entity name. Entity `GetTransferSummaryByClient`
becomes tool `get_transfer_summary_by_client`; the PascalCase form is not accepted.

**Approval policy** — `never`, which is safe only because every tool in the allowlist is read-only.

## Layers of control

The allowlist is the fourth and outermost gate. A tool must be permitted by all of:

1. The SQL grant to `mcp_reader`
2. The DAB entity permissions
3. The global `runtime.mcp.dml-tools` policy
4. This allowlist

Adding a tool here does not grant access. Removing one does prevent the agent from calling it.

## Identity notes

Keep the project managed identity, the shared project agent identity, and published agent identities
distinct. Grant developers `Foundry User` at project scope and consumers `Foundry Agent Consumer` at
individual-agent scope where possible. Downstream permissions must be reassigned to each published
agent identity — shared-project assignments do not transfer.

Do not claim per-user SQL row filtering unless an approved OBO/RLS design is implemented. Use
managed identity, never SQL credentials, and never generate unrestricted SQL.

## Instruction quality

Most incorrect answers trace back to entity and field descriptions in `dab-config.json` rather than
to these instructions. Before rewriting the prompt, confirm that `describe_entities` returns
populated field descriptions for every exposed entity.
