# Foundry Prompt Agents

This directory is reserved for code-first registration and evaluation assets for two project-native Microsoft Foundry v2 prompt agents:

- `transfer-agent-sql-mcp` uses the private SQL MCP Server and is the primary implementation.
- `transfer-agent-foundry-iq` uses the deferred Foundry IQ knowledge base MCP endpoint and is the comparison implementation.

The agents will be registered with `azure-ai-projects` 2.x using `AIProjectClient.agents.create_version` and `PromptAgentDefinition`. Each immutable version must be visible in the new Microsoft Foundry portal and Playground. These are prompt agents, not hosted-agent containers.

The agents must use the same model deployment, baseline instructions, domain language, and evaluation set. They differ only in tool configuration and tool-specific citation behavior.

No agent code, prompt, or tool registration is implemented yet. Phase 2 has deployed the shared `gpt-5.4-mini` model and Foundry project infrastructure.

When implementation begins:

- Keep the project managed identity, shared project agent identity, and published agent identities distinct.
- Grant developers `Foundry User` at project scope and consumers `Foundry Agent Consumer` at individual-agent scope where possible.
- Reassign downstream permissions to each published agent identity; shared-project assignments do not transfer.
- Do not claim per-user SQL row filtering unless an approved OBO/RLS or ACL-aware retrieval design is implemented.
- Use managed identity, never SQL credentials, and never generate unrestricted SQL.
