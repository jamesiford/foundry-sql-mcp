# Deployment Plan

## Status

Demo Deployment Complete - Azure SQL MCP Validated

## Active Demo Profile

The active branch is `demo/public-evaluation`. Its approved intent is to build a disposable, non-production public demonstration while preserving `main` as the secure private reference architecture.

Source roadmap: `docs/demo-roadmap.md`.

### Demo deployment decisions

- Create a new public Foundry Basic account/project; do not open or mutate the existing private Foundry account.
- Create new public ACR, Container Apps, and monitoring resources in `rg-foundry-sql-mcp-demo`.
- Create a disposable public Entra-only Azure SQL Database in the demo resource group.
- Do not modify the existing Central US SQL MI.
- Preserve Entra authentication, managed identities, synthetic-only data, named-object SQL grants, read-only DAB tools, and Foundry RBAC.
- Implement only SQL MCP Server and its prompt agent; Foundry IQ is out of scope for this branch.
- Treat all public endpoints as time-bounded evaluation exceptions and remove them during cleanup.
- Do not deploy or modify Azure resources until the user explicitly approves this plan.

### Planned demo environment

| Setting | Value |
|---|---|
| Subscription | `MCAPS-Internal-Non-Prod` |
| Subscription ID | `49d5f6b0-70f2-4563-acdc-9a31d2eee119` |
| Tenant ID | `16b3c013-d300-468d-ac64-7eda0820b6d3` |
| azd environment | `foundry-sql-mcp-demo` |
| Demo resource group | `rg-foundry-sql-mcp-demo` |
| Demo app location | `eastus2` |
| Demo SQL location | `centralus` |
| Demo branch | `demo/public-evaluation` |
| Demo SQL backend | Entra-only Azure SQL Database in `rg-foundry-sql-mcp-demo` |
| Demo data | Synthetic only |
| Demo posture | Public, Entra-authenticated, read-only, disposable |

East US 2 was selected for Foundry and Container Apps because the subscription has 2,580K TPM available for `gpt-5.4-mini` GlobalStandard and the prior private deployment encountered Container Apps capacity pressure in Central US. Azure SQL Database uses Central US because this subscription rejects new SQL logical servers in East US 2.

### Approval and execution gates

1. User approves `docs/demo-roadmap.md` and this deployment plan.
2. Validate model quota and choose a region that supports Foundry, the selected models, Search, and Container Apps.
3. Generate the separate demo infrastructure, SQL, MCP, prompt-agent, and evaluation artifacts.
4. Set plan status to `Ready for Validation`.
5. Run azure-validate checks, including Bicep build, what-if, credential scan, and role review.
6. Obtain deployment confirmation before creating resources.
7. Deploy and validate the SQL MCP demonstration.

### Explicitly out of scope for the demo

- Production or customer data.
- Anonymous MCP access.
- SQL usernames/passwords.
- Raw-table or arbitrary SQL exposure.
- Write tools.
- Per-user SQL row filtering claims.
- Foundry IQ, Azure AI Search knowledge sources, indexes/indexers, knowledge bases, embedding models, and an IQ comparison agent.
- Merging public network defaults into `main`.

### Demo validation proof

| Check | Result |
|---|---|
| `scripts/test-demo.ps1` | Passed: Bicep, DAB schema/policy, SQL ScriptDom, Python syntax, and image pin |
| Demo Bicep compile | Passed with zero diagnostics |
| `azd provision --preview --no-prompt` | Passed before deployment; subsequent provisions completed successfully and idempotently |
| Subscription ARM what-if | Passed before deployment; management-group SQL public-access mutation was handled with policy-compatible NSP |
| DAB 2.0.9 schema | Passed; live SQL connectivity validated after Azure SQL Database deployment |
| SQL syntax | Passed for all 5 files with Microsoft ScriptDom |
| PowerShell syntax | Passed for all scripts |
| Python SDK model construction | Passed with `azure-ai-projects==2.4.0` and `openai>=2.8.0` |
| Credential scan | Passed; no passwords, keys, tokens, or private keys |
| Role review | MCP UAMI receives only `AcrPull` in Azure and `mcp_reader` in SQL; no broad runtime role |
| Container App | Healthy, one replica, `RunningAtMaxScale`; anonymous data access returns `403` |
| Foundry agent smoke test | Passed all 3 deterministic prompts with grounded SQL results |
| Demo target | `rg-foundry-sql-mcp-demo` deployed; expiration `2026-08-13` |

### Deployment sequence after approval

1. Bootstrap the 13-resource public demo graph in East US 2.
2. Create the MCP Entra app role and assign it to the project identity.
3. Build the pinned DAB image in ACR.
4. Provision the Entra-only Azure SQL Database and enforced Network Security Perimeter.
5. Deploy the synthetic schema/data and direct-SID `mcp_reader` authorization.
6. Re-provision to create the SQL MCP Container App and Foundry RemoteTool connection.
7. Register and smoke-test `transfer-agent-sql-mcp-demo`.
8. Provide the public Foundry Playground URL and run the demonstration prompts.

### Live deployment status

- Public demo bootstrap succeeded in East US 2: Foundry Basic account/project, `gpt-5.4-mini`, ACR, Container Apps environment, UAMI, Log Analytics, and Application Insights.
- Foundry public network access is enabled and local/key authentication is disabled.
- MCP UAMI has only `AcrPull` in Azure.
- Entra app `foundry-sql-mcp-demo-api`, audience `api://ab2bfe51-53cb-4387-b90f-3dc2990371dd`, and `Mcp.Invoke` assignment to the project identity succeeded.
- Pinned DAB 2.0.9 image `sql-mcp:2.0.9-0d4a93e-4b2945a8` was built from the implementation commit and pushed with digest `sha256:61923e5183f2f46772ade50e2f2ea108852e1e81271cdf309e516bf9ac4b3af0`.
- The SQL MI experiment was rolled back: partial `TransferDemo` removed, demo NSG rule removed, public endpoint disabled, and stop submitted.
- Azure SQL Database is the approved replacement because it supports direct client-ID SID user creation without SQL MI Directory Readers.
- Azure SQL Database `sqlsqlmcpdemog64t67` and Basic database `TransferDemo` are online in Central US.
- Management-group policy `AzureSQL_PublicNetwork_Modify` requires ordinary SQL public access to remain disabled; the deployed server uses `SecuredByPerimeter` and an enforced NSP profile instead of firewall rules.
- Synthetic schema/data, four approved views, three approved procedures, `mcp_reader`, and the direct-SID MCP UAMI user were deployed successfully.
- The RemoteTool connection explicitly enables project managed identity. Foundry requests tokens for `api://ab2bfe51-53cb-4387-b90f-3dc2990371dd`; the resulting v2 token uses the bare client ID as `aud` and contains `Mcp.Invoke`.
- The MCP service principal requires app-role assignment. DAB authorizes both its MCP-selected `Mcp.Invoke` role and system `authenticated` role with identical read/execute-only permissions; generic execute and all write tools remain disabled.
- Agent `transfer-agent-sql-mcp-demo:2` is registered with mandatory custom-report tool routing. All three smoke prompts returned grounded transfer, risk, and advisor-pipeline data.

## Phase 1 Scope

Phase 1 repository scaffold only. This phase creates documentation, Azure Developer CLI configuration, syntactically valid non-deploying Bicep module placeholders, setup/deploy helper stubs, and source-area contracts.

## Phase 1 Historical Deferrals

- Azure resource provisioning (implemented in Phase 2)
- Microsoft Foundry resource, project, model, or agent runtime implementation
- Azure SQL Managed Instance and database implementation
- Synthetic data generation or seeding
- Microsoft SQL MCP Server and Data API builder implementation
- Foundry IQ knowledge source or knowledge base configuration
- Runtime role assignments and SQL permissions (Azure dependency roles are implemented; SQL roles remain deferred)
- Deployment execution (started in Central US on 2026-07-13)

## Current Architecture Direction

- Azure Developer CLI orchestrates subscription-scope Bicep.
- Two separate Microsoft Foundry prompt agents will expose Foundry IQ semantic retrieval and SQL MCP deterministic operations.
- Azure SQL Managed Instance remains private and Entra-authenticated.
- Runtime identities remain separate and least privileged.
- Monitoring uses Log Analytics and Application Insights.

## Phase 1 Artifacts

- Repository guidance and root configuration
- Architecture, security, integration, and decision documentation
- Bicep entry point and module placeholders
- Cross-platform local setup and deployment helper scripts
- Source-area README contracts

## Security Decisions

- No secrets, credentials, tokens, or connection strings are committed.
- No SQL authentication parameters are defined.
- No broad runtime permissions are assigned.
- Placeholder modules deploy no Azure resources in Phase 1.

## Validation

- [x] Compiled `infra/main.bicep` with no diagnostics.
- [x] Parsed `infra/main.parameters.json`.
- [x] Confirmed `azure.yaml` is accepted by Azure Developer CLI.
- [x] Parsed all PowerShell scripts and checked shell scripts with Git Bash.
- [x] Ran `scripts/smoke-test.ps1` successfully.
- [x] Completed the required-file inventory and found no credential-like values or private keys.

## Current Deployment Outcome

The Central US deployment created the resource group, VNet, monitoring, managed identity, Entra-only SQL MI, private Storage/Cosmos/Search dependencies, Foundry resource and project, `gpt-5.4-mini`, project connections, private endpoints, and project capability host. SQL MI reached `Ready`, and `caphostproj` reached `Succeeded`.

The internal Container Apps environment `cae-sql-mcp-d3q5zq` failed with `ManagedEnvironmentCapacityHeavyUsageError` / `AKSCapacityHeavyUsage`. This was a regional platform-capacity failure, not a Bicep validation or subscription-quota failure. Retry the validated deployment idempotently after confirming Azure CLI and azd are authenticated to tenant `16b3c013-d300-468d-ac64-7eda0820b6d3`. Do not advance to Phase 3 until the environment and generated private DNS resources succeed and Phase 2 post-deployment checks pass.

## Confirmed Phase 2 Context

| Setting | Value |
|---|---|
| Subscription | `MCAPS-Internal-Non-Prod` |
| Subscription ID | `49d5f6b0-70f2-4563-acdc-9a31d2eee119` |
| Tenant ID | `16b3c013-d300-468d-ac64-7eda0820b6d3` |
| azd environment | `foundry-sql-mcp-dev-centralus` |
| Location | `centralus` |
| Planned resource group | `rg-foundry-sql-mcp-dev-centralus` |
| Planned VNet | `10.50.0.0/16` |
| SQL MI | Cost-minimized non-production configuration with Entra-only administration |
| Preview features | Allowed when version-pinned, documented, and validated |

The initial `westus3` deployment was canceled after Azure SQL Managed Instance returned `ProvisioningDisabled`. The subscription's controlling regional quotas were `0` SQL MI subnets and `0` SQL MI vCores. The partial West US 3 resource group, Foundry tombstone, service association link, and VNet were subsequently deleted.

`centralus` was selected after confirming 8 available SQL MI subnet slots, 960 available controlling MI vCores, `gpt-5.4-mini` availability, Foundry Agent Service support, MCP and Responses support, and Class A private networking support.

## Phase 2 Architecture Decisions

- The private SQL MCP path is the primary implementation path.
- Foundry Agent Service uses Standard Agent Setup with BYO VNet because private MCP isn't supported by Basic Agent Setup.
- Microsoft SQL MCP Server/Data API builder runs in an internal-only Azure Container Apps environment on a dedicated delegated subnet.
- MCP authenticates to SQL MI with its user-assigned managed identity and uses the VNet-local endpoint on TCP `1433`.
- SQL MI public data endpoint remains disabled by default.
- A private Azure AI Search service is required and provisioned for Standard Agent Setup vector-store state.
- The Azure SQL knowledge source, indexer, retrieval index, Foundry IQ knowledge base, IQ project connection, and IQ agent are deferred.
- Two project-native prompt agents will be registered with `azure-ai-projects` 2.x and `PromptAgentDefinition`:
	- `transfer-agent-sql-mcp` is the primary agent.
	- `transfer-agent-foundry-iq` is the deferred comparison agent.
- Both agent versions use the same model, baseline instructions, and evaluation set; their tool configuration is the controlled difference.
- Registered prompt-agent versions must surface in the new Microsoft Foundry portal and Playground.

## Deferred Foundry IQ Profile

The optional IQ profile defaults to disabled. If enabled later, it may use the SQL MI public endpoint on TCP `3342`, Search managed identity, TLS, approved-view `SELECT`, and NSG sources limited to the Search service IP plus required `AzureCognitiveSearch` ranges. MCP remains on the private TCP `1433` path.

Search shared private link to SQL MI is currently rejected because its documented preview implementation requires a SQL username/password. Preview status is acceptable; introducing SQL credentials is not.

## Phase 2 Execution Order

1. Confirm provider registrations, quotas, naming, APIs, and deployable SKUs in `centralus`.
2. Add typed parameters and naming outputs.
3. Implement the resource group, VNet, SQL MI subnet, Standard Agent Setup network requirements, and dedicated MCP subnet.
4. Implement managed identities, Log Analytics, and Application Insights.
5. Implement Entra-only SQL MI and private DNS/connectivity.
6. Implement Foundry resource/project/model infrastructure and private agent networking.
7. Implement the internal Container Apps environment and SQL MCP workload boundary.
8. Implement only the minimum Azure role assignments required by those resources.
9. Compile Bicep, run lint and security checks, run subscription-scope what-if, and invoke `azure-validate` before deployment.

Database schema, synthetic data, database users/roles, Data API builder configuration, MCP tools, and prompt-agent registration remain in their designated implementation phases, but the SQL MCP path will be completed before Foundry IQ work begins.

## Phase 2 Validation Checks

- [x] AZD installation
- [x] `azure.yaml` schema validation
- [x] azd environment setup
- [x] Azure CLI and azd authentication check
- [x] Subscription and location confirmation
- [x] Aspire pre-provisioning checks (not applicable; this isn't an Aspire project)
- [x] `azd provision --preview --no-prompt`
- [x] Root and module Bicep build verification
- [x] Docker build-context validation (not applicable; no deployable service or Dockerfile exists in this phase)
- [x] Package validation (not applicable; `azure.yaml` defines infrastructure only)
- [x] Azure Policy review and subscription-scope ARM what-if
- [x] Aspire post-provisioning checks (not applicable)
- [x] Credential-pattern scan
- [x] PowerShell, Bash, JSON, YAML, and Markdown-link validation

## Role Assignment Verification

- Status: Verified statically against the official Standard Agent Setup pattern.
- Foundry project identity:
	- Storage Blob Data Contributor on the Standard Setup storage account.
	- Storage Blob Data Owner constrained by an ABAC condition to project-prefixed `*-azureml-agent` containers.
	- Cosmos DB Operator on the Standard Setup Cosmos DB account.
	- Cosmos DB Built-in Data Contributor at the account data-plane scope.
	- Search Index Data Contributor and Search Service Contributor on the Standard Setup Search service.
- Deployment user:
	- Foundry User on the new Foundry project only.
- MCP user-assigned identity:
	- No Azure role assignment yet because the MCP Container App, registry, and SQL contained user are deferred.
	- Phase 4 will create its SQL contained user and grant only the custom MCP database role.
- Broad runtime roles found: none.
- SQL authentication parameters found: none.

## Validation Proof

| Check | Result |
|---|---|
| `az bicep build --file infra/main.bicep --stdout` | Passed; zero compiler diagnostics |
| `scripts/smoke-test.ps1` | Passed |
| PowerShell AST and Bash syntax checks | Passed |
| `infra/main.parameters.json` parsing | Passed |
| `azd show` / `azure.yaml` schema | Passed |
| `azd auth login --check-status` | Passed as `fordjames@microsoft.com` |
| `azd env get-values` | Correct subscription, tenant, `centralus`, model, and Entra principal IDs configured |
| Provider registration | Required providers registered, including `Microsoft.MachineLearningServices` |
| Deployment identity | Subscription Owner; can create required narrow role assignments |
| Model | `gpt-5.4-mini` `2026-03-17` is GA in `centralus`, supports Agents v2 and Responses, and offers `GlobalStandard` |
| SQL MI | Central US has 8 available SQL MI subnet slots and 960 available controlling MI vCores; the planned General Purpose instance requires one subnet and 4 vCores |
| Target resource group | `rg-foundry-sql-mcp-dev-centralus` was created by the partial deployment |
| `azd provision --preview --no-prompt` | Passed for `centralus`; create-only preview with the expected resource group, Foundry project, `gpt-5.4-mini` deployment, private dependencies, and no deletes |
| Subscription-scope ARM what-if | Passed; 54 explicit creates and 9 expected runtime-resolved resources, with no deletes or validation errors |
| Azure Policy assignments | Reviewed; no deny policy identified for this resource graph |
| Credential-pattern scan | Passed; no SQL passwords, keys, SAS tokens, or private keys |
| Central US deployment | Partially succeeded; SQL MI, Foundry account/project/model, Search, Cosmos DB, Storage, monitoring, private endpoints, and project capability host succeeded |
| Container Apps environment | Failed with regional `AKSCapacityHeavyUsage`; idempotent retry required |
