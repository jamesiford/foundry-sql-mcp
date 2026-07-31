# Portal-First Public SQL MCP Setup

This runbook recreates the simplified `demo/public-evaluation` environment. It uses Azure and Microsoft Foundry portals for resource configuration and the repository scripts for artifact operations that the portals don't perform reliably: validating Bicep/DAB, building the pinned container image, applying SQL migrations, assigning an application role to a managed identity, and registering an immutable prompt-agent version.

The deployed environment is public for evaluation, contains synthetic data only, and expires on the date selected by the operator. It does not deploy Foundry IQ, Azure AI Search, a VNet, or private endpoints.

> [!IMPORTANT]
> This is a demo runbook, not the customer production runbook. It does not assume that a customer will permit public database access. Customer Azure SQL Database should use private endpoints where required, SQL Managed Instance should use its private VNet endpoint, and on-premises SQL Server should use local placement or VPN/ExpressRoute. See [SQL Backend Options](sql-backend-options.md).

## Choose your deployment path

> [!TIP]
> **Recommended fast path: deploy with IaC.** You do not need to perform every portal step manually. Use the repository's idempotent `azd up` workflow to provision and configure the complete public demo. Use the numbered portal sections when you want to understand each component, verify the deployment, or recover one stage selectively.

| Path | Choose it when | Result |
|---|---|---|
| **IaC with `azd up`** | You want a repeatable, validated deployment with the least manual work | Provisions Azure resources and completes Entra, DAB, SQL, Foundry connection, agent registration, and smoke tests |
| **Portal walkthrough** | You are learning the architecture, need customer-facing screenshots, or must configure/review resources individually | Produces the same architecture through explicit portal and script steps |

> [!WARNING]
> **Portability is conditional, not universal.** The workflow is validated end to end in the reference MCAPS tenant/subscription on Windows with PowerShell 7. Tenant and subscription IDs are parameterized, but each customer must pass the preflight below. Tenant policy, unavailable providers/SKUs, model quota, regional capacity, or insufficient Entra privileges can block deployment.

### Customer preflight

| Requirement | Customer validation |
|---|---|
| Deployment workstation | Windows with PowerShell 7, Git, Azure CLI, azd, Python 3, .NET SDK, and `winget`; other operating systems are not yet validated by this workflow |
| Azure context | An active subscription in the intended tenant; pass both IDs explicitly to environment setup |
| Azure permissions | Permission to create the documented resources and Azure role assignments in the target subscription/resource group |
| Entra permissions | Permission to create/update an app registration and service principal and assign its application role to the Foundry project identity |
| Resource providers | `Microsoft.CognitiveServices`, `Microsoft.App`, `Microsoft.Sql`, `Microsoft.Network`, `Microsoft.ContainerRegistry`, `Microsoft.OperationalInsights`, `Microsoft.Insights`, and `Microsoft.ManagedIdentity` available/registered |
| Foundry/model | Foundry project creation and `gpt-5.4-mini` deployment supported in the selected app region, with sufficient model quota/capacity |
| Azure SQL | Logical-server/database creation allowed in the selected SQL region and Entra-only administrator assignment permitted |
| NSP | Network Security Perimeter and `SecuredByPerimeter` supported and permitted; this is a reference-subscription demo workaround, not a universal customer requirement |
| Network/policy | No deny/modify policy conflicts beyond those explicitly handled by the template |

If the customer requires private Azure SQL, SQL MI, on-premises SQL Server, a different model, or a non-Windows deployment host, adapt and validate the appropriate profile in [SQL Backend Options](sql-backend-options.md) before using this command.

### IaC prerequisites

Install these tools on the deployment workstation:

- PowerShell 7
- Git
- Azure CLI
- Azure Developer CLI (`azd`)
- Python 3
- .NET SDK
- `winget` on Windows

The `preup` hook installs or converges Data API builder 2.0.9, modern sqlcmd, the workspace Python virtual environment, and pinned agent SDK packages. The operator still needs the Azure/Entra permissions listed under [Required access](#required-access).

Authenticate and select the approved branch, subscription, and tenant:

```powershell
git switch demo/public-evaluation
$tenantId = '<customer-tenant-id>'
$subscriptionId = '<customer-subscription-id>'
az login --tenant $tenantId
az account set --subscription $subscriptionId
azd auth login --tenant-id $tenantId
```

Create or refresh the non-secret azd environment. Choose the approved expiration date for the disposable resources:

```powershell
./scripts/setup-demo-environment.ps1 `
  -EnvironmentName foundry-sql-mcp-demo `
  -SubscriptionId $subscriptionId `
  -TenantId $tenantId `
  -Location <validated-app-region> `
  -SqlLocation <validated-sql-region> `
  -ExpirationDate <yyyy-mm-dd>
```

Preview the control-plane deployment if required by your change process:

```powershell
azd provision --preview --environment foundry-sql-mcp-demo --no-prompt
```

Run the complete deployment:

```powershell
azd up --environment foundry-sql-mcp-demo --no-prompt
```

### What `azd up` completes

The root hooks in `azure.yaml` make `azd up` an end-to-end workflow:

1. Validates Bicep, DAB, SQL, Python, and local prerequisites.
2. Creates or reconciles Foundry, the model deployment, monitoring, ACR, managed identity, Container Apps environment, Azure SQL Database, and the demo NSP.
3. Creates or reconciles the Entra MCP application, `Mcp.Invoke` app role, assignment-required service principal, and project-identity assignment.
4. Reuses or builds the content-addressed DAB 2.0.9 image.
5. Applies idempotent SQL schema, seed, view, procedure, role, and contained-user migrations. Temporary SQL bootstrap access is always restored in `finally`.
6. Performs the image-dependent Bicep pass for the Container App and Foundry RemoteTool connection.
7. Reuses an unchanged prompt-agent version or creates a new version only when its definition changes.
8. Verifies Container App health and runs the three deterministic agent smoke tests.

The workflow is idempotent. Re-running the same source state reconciles resources without duplicating Entra assignments, SQL records, ACR image content, or agent versions. A repeat run was validated with unchanged Azure resource count, image-tag count, agent-version count, and active image.

After the command succeeds, open **Microsoft Foundry portal > `project-foundry-sql-mcp-demo` > Build > Agents > `transfer-agent-sql-mcp-demo` > Playground**. Continue with [Validate in the portals](#14-validate-in-the-portals) for the manual review checklist.

## Components and why they exist

Read this section before creating resources. The solution separates model hosting, agent orchestration, MCP hosting, database access, and identity so each principal and service can receive only the access it needs.

| Component | What it is | Why this solution needs it |
|---|---|---|
| Repository, Bicep, and Azure Developer CLI (`azd`) | The versioned source and deployment tooling for infrastructure, SQL, DAB configuration, and agent registration | Makes the portal walkthrough reproducible and prevents undocumented portal drift |
| Azure resource group | A lifecycle and access-management boundary for related Azure resources | Keeps the disposable demo isolated, tagged, auditable, and removable as one unit |
| Log Analytics workspace | Azure's central log store and query engine | Receives platform and NSP diagnostics used to troubleshoot denied SQL traffic |
| Application Insights | Azure application performance and distributed telemetry service | Provides the Foundry project monitoring connection and a place for application telemetry as instrumentation is enabled |
| User-assigned managed identity (UAMI) | An Entra workload identity whose lifecycle is independent of one compute resource | Lets DAB pull its image and authenticate to Azure SQL without passwords |
| Azure Container Registry (ACR) | A private registry for OCI/Docker container images | Stores the pinned, configuration-specific SQL MCP Server image |
| Container Apps environment | The shared Azure Container Apps hosting boundary for networking, logging, and revisions | Provides serverless container hosting without managing Kubernetes |
| SQL MCP Container App | The running DAB 2.0.9 container with HTTPS ingress | Hosts the `/mcp` endpoint that Foundry calls and uses the UAMI to reach SQL |
| Microsoft Foundry resource | The Azure account-level boundary for models, projects, RBAC, and connections | Hosts the model deployment and the project used by the demo agent |
| Foundry project | The development and runtime boundary for agents, tools, connections, and project identity | Owns the RemoteTool connection and supplies the managed identity used to call MCP |
| Model deployment | A named deployment of `gpt-5.4-mini` with allocated capacity | Provides the reasoning model used by the prompt agent |
| Prompt agent | A versioned Foundry agent definition containing model, instructions, and allowed tools | Converts user requests into approved SQL MCP tool calls and summarizes grounded results |
| Azure SQL logical server | The management and authentication boundary for Azure SQL databases | Supplies the Entra administrator, TLS/network settings, and database endpoint |
| Azure SQL Database | The managed relational database containing the synthetic transfer dataset | Stores the tables while exposing only curated views and stored procedures to MCP |
| Network Security Perimeter (NSP) | An Azure network boundary for supported PaaS resources with explicit access rules | Required only in this demo subscription because policy disables ordinary Azure SQL public access; it is not a SQL MCP requirement |
| Entra application registration | The definition of the SQL MCP API audience and `Mcp.Invoke` application role | Gives Foundry a target audience for token acquisition and restricts token issuance to assigned workloads |
| Enterprise application/service principal | The tenant-local instance of the Entra application | Enforces assignment-required and holds the Foundry project identity's `Mcp.Invoke` assignment |
| SQL MCP Server / Data API builder (DAB) | Microsoft's SQL MCP Server runtime, configured by `dab-config.json` | Converts structured MCP calls into deterministic, permission-checked SQL operations without NL2SQL |
| `dab-config.json` | DAB's declarative contract for data source, authentication, tools, entities, fields, and permissions | Determines exactly which database objects and operations agents can discover and invoke |
| Curated SQL contract | Four views, three stored procedures, role `mcp_reader`, and the MCP contained user | Keeps raw tables and writes outside the agent-facing boundary even if another layer is misconfigured |
| Foundry RemoteTool connection | Project metadata describing the MCP URL, audience, and authentication identity | Tells Agent Service where MCP is and how to obtain the Entra token sent to it |

### Identity flow

The identities are intentionally different:

1. The human setup operator creates/configures resources and applies SQL migrations.
2. The Foundry project system-assigned identity calls the MCP endpoint and must have `Mcp.Invoke` on the MCP enterprise application.
3. The MCP UAMI runs with the Container App, pulls from ACR, and connects to SQL as the contained database user in `mcp_reader`.
4. End users invoke the agent through Foundry RBAC; they do not receive direct SQL access from that role.

## Target architecture

```mermaid
flowchart LR
    User[Foundry Playground user] --> Foundry[Public Foundry Basic project]
    Foundry --> Agent[SQL MCP prompt agent]
    Agent -->|Project MI + Entra token| MCP[Public DAB SQL MCP Container App]
    MCP -->|UAMI + TLS 1433| SQL[(Azure SQL Database)]
    NSP[Enforced Network Security Perimeter] --> SQL
```

## Reference values

| Setting | Value |
|---|---|
| Subscription | `MCAPS-Internal-Non-Prod` (`49d5f6b0-70f2-4563-acdc-9a31d2eee119`) |
| Tenant | `16b3c013-d300-468d-ac64-7eda0820b6d3` |
| Resource group | `rg-foundry-sql-mcp-demo` |
| Foundry/Container Apps region | East US 2 |
| SQL/NSP region | Central US |
| Foundry project | `project-foundry-sql-mcp-demo` |
| Model deployment | `gpt-5.4-mini`, version `2026-03-17`, Global Standard, capacity 10 |
| SQL database | `TransferDemo`, Basic, 2 GB |
| DAB version | `2.0.9` |
| Agent | `transfer-agent-sql-mcp-demo` |

The split regions are deliberate. This subscription rejects new Azure SQL logical servers in East US 2, while Central US previously had Container Apps capacity pressure.

## Required access

Use separate privileged and runtime identities. The setup operator needs enough temporary access to create resources, role assignments, an Entra application, and the SQL Entra administrator. Runtime identities must not receive `Owner`, `Contributor`, `db_owner`, `db_datareader`, or `db_datawriter`.

| Principal | Required access |
|---|---|
| Setup operator | Resource deployment and role-assignment rights in the demo subscription; permission to create/configure an Entra application |
| Agent developer | `Foundry User` on the demo project |
| Foundry project identity | `Foundry User` on the Foundry resource; `Mcp.Invoke` on the MCP Entra application |
| MCP user-assigned identity | `AcrPull` on ACR; `mcp_reader` in `TransferDemo` |
| Demo consumer | `Foundry Agent Consumer` on the agent where available |

## 1. Prepare the repository and Azure context

**What it is:** The repository is the versioned source of truth; `azd` binds that source to one named Azure environment and stores non-secret deployment values.

**Why it is needed:** Portal resources alone don't preserve the exact DAB config, SQL contract, Bicep state, or agent definition. Selecting the branch and tenant prevents deploying the demo into the wrong environment.

**How to configure it:**

```powershell
git switch demo/public-evaluation
az account set --subscription 49d5f6b0-70f2-4563-acdc-9a31d2eee119
az account show --query "{user:user.name,tenant:tenantId,subscription:id}" -o table
azd auth login --check-status
```

Create or refresh the non-secret azd environment values:

```powershell
./scripts/setup-demo-environment.ps1 `
  -SubscriptionId 49d5f6b0-70f2-4563-acdc-9a31d2eee119 `
  -TenantId 16b3c013-d300-468d-ac64-7eda0820b6d3 `
  -Location eastus2 `
  -SqlLocation centralus `
  -ExpirationDate <yyyy-mm-dd>
```

The script records the signed-in user's Entra object ID and UPN plus the direct and Azure-routed client IPs needed by the SQL perimeter profile.

For the complete repository-driven deployment, `azure.yaml` registers idempotent `preup` and `postup` hooks. After the environment is selected, this one command performs all numbered implementation phases and smoke validation:

```powershell
azd up --environment foundry-sql-mcp-demo
```

The portal steps below explain the resources that command creates and are also useful for inspection or targeted recovery.

## 2. Create the resource group and monitoring

**What they are:** The resource group is the demo lifecycle boundary. Log Analytics stores diagnostic records; Application Insights is the application-monitoring resource linked to the Foundry project.

**Why they are needed:** The resource group enables one-command cleanup and scoped review. Monitoring provides deployment/runtime visibility and, critically for this subscription, records NSP allow/deny decisions.

**How to configure them:**

In **Azure portal > Resource groups > Create**:

1. Select subscription `MCAPS-Internal-Non-Prod`.
2. Name the group `rg-foundry-sql-mcp-demo`.
3. Select **East US 2**.
4. Add tags: `application=foundry-sql-mcp`, `purpose=public-evaluation`, `dataClassification=synthetic`, and the approved `expirationDate`.

In that resource group:

1. Create a **Log Analytics workspace** in East US 2 with 30-day retention.
2. Create **Application Insights** in East US 2, workspace-based, connected to that workspace.
3. Keep public ingestion and query enabled for this disposable demo.

The deployed reference names are `law-sql-mcp-demo-btqgzq` and `appi-sql-mcp-demo-btqgzq`.

## 3. Create the MCP identity and container registry

**What they are:** The UAMI is DAB's passwordless workload identity. ACR stores the DAB container image built from the repository configuration.

**Why they are needed:** The identity keeps registry and SQL credentials out of source/configuration. ACR gives Container Apps a controlled, immutable image source.

**How to configure them:**

In **Azure portal > Managed Identities > Create**:

1. Create a user-assigned identity in East US 2.
2. Use name `id-mcp-foundry-sql-mcp-demo`.
3. Record both its **Client ID** and **Object (principal) ID**. SQL direct-SID user creation uses the client ID; Azure RBAC uses the principal ID.

In **Azure portal > Container registries > Create**:

1. Create a **Basic** registry in East US 2, such as `acrsqlmcpdemobtqgzq`.
2. Keep public network access enabled and the admin user disabled.
3. Open **Access control (IAM) > Add role assignment**.
4. Assign `AcrPull` to `id-mcp-foundry-sql-mcp-demo` at registry scope.

Do not grant the MCP identity `Contributor` on the registry or resource group.

## 4. Create the public Container Apps environment

**What it is:** A Container Apps environment is the shared hosting, logging, revision, and networking boundary in which the SQL MCP Container App runs.

**Why it is needed:** SQL MCP Server is self-hosted software. Container Apps runs the pinned Linux container with HTTPS ingress and managed identity without requiring an AKS cluster.

**How to configure it:**

In **Azure portal > Container Apps Environments > Create**:

1. Select `rg-foundry-sql-mcp-demo` and East US 2.
2. Use a public, non-VNet-integrated environment such as `cae-sql-mcp-demo-btqgzq`.
3. Connect it to the demo Log Analytics workspace.
4. Do not create a workload Container App yet; its image and SQL authorization are prepared in later steps.

## 5. Create the Foundry resource, project, and model

**What they are:** The Foundry resource is the account-level Azure boundary; the project owns agents/connections and has its own identity; the model deployment supplies inference capacity.

**Why they are needed:** The project identity authenticates to MCP, the model decides which approved tool to invoke, and the project registers the versioned prompt agent visible in Playground.

**How to configure them:**

In **Azure portal > Microsoft Foundry > Create**:

1. Create an AI Services/Foundry resource in East US 2 using **Basic agent setup**.
2. Enable the system-assigned managed identity.
3. Keep public network access enabled and local/key authentication disabled.
4. Create project `project-foundry-sql-mcp-demo` with its system-assigned managed identity enabled.
5. Do not configure Standard Agent Setup dependencies, VNet injection, private endpoints, Storage, Cosmos DB, or Search for this demo.

In **Microsoft Foundry portal > Models + endpoints**:

1. Deploy `gpt-5.4-mini`.
2. Pin version `2026-03-17`.
3. Select **Global Standard** and capacity `10`.
4. Name the deployment `gpt-5.4-mini`.

In **Azure portal > Foundry resource > Access control (IAM)**:

1. Assign `Foundry User` to the project system-assigned identity at the Foundry-resource scope.
2. Assign the setup developer `Foundry User` at project scope.

Record the project identity's principal ID. The deployed reference project identity is `03b96314-4cf2-4051-9910-ce2cb90bf976`.

## 6. Create Entra-only Azure SQL Database

**What it is:** Azure SQL Database is the managed relational backend. Its logical server controls Entra administration, network policy, TLS, and the database hostname.

**Why it is needed:** The demo needs deterministic relational data for SQL MCP tools. Entra-only authentication removes SQL passwords, while Azure SQL Database supports direct client-ID SID creation for the MCP UAMI.

**How to configure it:**

In **Azure portal > Azure SQL > Create > SQL database**:

1. Select `rg-foundry-sql-mcp-demo` and create a new logical server in **Central US**.
2. Name the database `TransferDemo`.
3. Under **Compute + storage**, select **Basic**, 5 DTUs, with a 2-GB maximum.
4. Under **Authentication**, select **Microsoft Entra-only authentication**.
5. Set the signed-in deployment user or an approved Entra group as server administrator.
6. Do not configure a SQL administrator login or password.
7. Set minimum TLS to `1.2`.
8. Create the database with public network access disabled initially. The NSP association supplies the approved data-plane path in the next step.

The deployed logical server is `sqlsqlmcpdemog64t67.database.windows.net`.

## 7. Protect SQL with Network Security Perimeter

**What it is:** NSP is a policy-aware PaaS network boundary with profiles, inbound/outbound rules, associations, and diagnostic logs.

**Why it is needed here:** It is not required by SQL MCP Server or by the customer design. This demo subscription has management-group policy that forces ordinary Azure SQL public network access off, so NSP is the available public-evaluation path between non-VNet Container Apps and SQL.

**How to configure it:**

The subscription has management-group policy `AzureSQL_PublicNetwork_Modify`, which disables ordinary SQL public access. Do not bypass it with an old API version or broad SQL firewall rule.

In **Azure portal > Network Security Perimeters > Create**:

1. Create `nsp-sql-mcp-demo-<suffix>` in Central US.
2. Create profile `sql-mcp-demo`.
3. Add inbound rule `allow-demo-subscription` with source type **Subscriptions** and subscription `49d5f6b0-70f2-4563-acdc-9a31d2eee119`.
4. Add inbound rule `allow-demo-clients` with only the operator CIDR `/32` addresses recorded by `setup-demo-environment.ps1` as `DEMO_CLIENT_IP` and `DEMO_AZURE_CLIENT_IP`.
5. Associate the Azure SQL logical server with profile `sql-mcp-demo`.
6. Change the association from learning/audit to **Enforced**.
7. Set the SQL server's public network mode to **Secured by perimeter**.
8. Add a diagnostic setting that sends `allLogs` to the demo Log Analytics workspace.

Validate in the SQL server's **Networking** blade that no SQL firewall rules exist. The subscription rule is an evaluation-only accommodation for non-VNet Container Apps egress; production SQL MI uses private networking instead.

Azure portal Query Editor and corporate-routed SSMS/sqlcmd traffic can use backend TDS addresses that differ from `ipify` and the ARM token IP. After one denied connection attempt, wait for NSP diagnostics to ingest and reconcile only the observed `/32`s:

```powershell
./scripts/update-demo-sql-client-ips.ps1 -LookbackHours 2 -Provision
```

The helper stores the additional addresses in `DEMO_ADDITIONAL_CLIENT_IPS`, so later `azd provision` runs preserve them. Re-run it if the portal or corporate egress pool changes. If logs prove that addresses rotate within one small contiguous range, replace its accumulated `/32`s with the narrowest observed CIDR, such as `/24`; do not use `0.0.0.0/0`.

## 8. Configure the MCP Entra application

**What it is:** The app registration defines the MCP API identifier and `Mcp.Invoke` application permission. Its enterprise application is the tenant object on which assignment-required and workload assignments are enforced.

**Why it is needed:** Foundry needs an audience for its managed-identity token. Requiring assignment prevents unassigned tenant identities from acquiring an application token for this MCP API.

**How to configure it:**

In **Microsoft Entra admin center > App registrations > New registration**:

1. Create a single-tenant application named `foundry-sql-mcp-demo-api`.
2. Under **Expose an API**, set the Application ID URI to `api://<application-client-id>`.
3. Under **App roles**, create an application role:
   - Display name: `Invoke SQL MCP`
   - Allowed member types: **Applications**
   - Value: `Mcp.Invoke`
   - Enabled: Yes
4. Open the corresponding **Enterprise application > Properties** and set **Assignment required?** to Yes.

The portal does not reliably assign an application role to a managed identity. Use the repository script to reconcile the app, enforce assignment-required, assign `Mcp.Invoke` to the Foundry project identity, and store only non-secret IDs in azd:

```powershell
$values = azd env get-values --output json | ConvertFrom-Json
./scripts/setup-demo-entra.ps1 `
  -ProjectPrincipalId $values.AZURE_AI_PROJECT_PRINCIPAL_ID `
  -TenantId $values.AZURE_TENANT_ID
$values = azd env get-values --output json | ConvertFrom-Json
```

Keep these two audience forms distinct:

- Foundry RemoteTool connection audience: `api://<application-client-id>`.
- DAB expected JWT `aud` claim: the bare `<application-client-id>` GUID.

Foundry sends a tenant-v2 token containing `Mcp.Invoke`. The project connection must explicitly enable use of the project managed identity.

## 9. Configure and build SQL MCP Server

**What it is:** SQL MCP Server is the MCP capability included in Data API builder. The committed configuration is [src/mcp-server/dab-config.json](../src/mcp-server/dab-config.json), and the pinned container definition is [src/mcp-server/Dockerfile](../src/mcp-server/Dockerfile).

**Why it is needed:** Foundry doesn't query SQL directly. DAB provides the deterministic entity abstraction, JWT validation, RBAC, structured SQL generation, field metadata, and MCP protocol endpoint between the agent and database.

**How to configure it:** Treat `dab-config.json` as the server's public data contract: it controls the database connection, authentication, MCP tools, exposed objects, field metadata, and permitted operations.

### Pin the schema and database provider

The configuration pins the DAB 2.0.9 schema and selects the `mssql` provider:

```json
{
  "$schema": "https://github.com/Azure/data-api-builder/releases/download/v2.0.9/dab.draft.schema.json",
  "data-source": {
    "database-type": "mssql",
    "connection-string": "@env('DATABASE_CONNECTION_STRING')",
    "options": {
      "set-session-context": false
    }
  }
}
```

Do not put a credential-bearing connection string in this file. The Container App supplies `DATABASE_CONNECTION_STRING` at runtime. This demo uses managed identity, TLS encryption, certificate validation, the UAMI client ID, and database `TransferDemo`.

### Configure the runtime and MCP tools

The `runtime` section enables streamable HTTP MCP at `/mcp`, disables GraphQL, and configures Entra JWT validation:

```json
{
  "runtime": {
    "graphql": { "enabled": false },
    "mcp": {
      "enabled": true,
      "path": "/mcp",
      "dml-tools": {
        "describe-entities": true,
        "create-record": false,
        "read-records": true,
        "update-record": false,
        "delete-record": false,
        "execute-entity": false,
        "aggregate-records": {
          "enabled": true,
          "query-timeout": 30
        }
      }
    },
    "host": {
      "authentication": {
        "provider": "EntraID",
        "jwt": {
          "audience": "00000000-0000-0000-0000-000000000000",
          "issuer": "https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111/v2.0"
        }
      },
      "mode": "production"
    }
  }
}
```

The all-zero audience and all-ones tenant are build-time placeholders. `build-demo-mcp.ps1` replaces them in the ignored build context with the MCP application's **bare client ID** and selected tenant ID. Keep the Foundry project connection audience as `api://<client-id>`; these values are intentionally different.

The global tool policy is read-only:

- `describe_entities`, `read_records`, and `aggregate_records` are available for approved views.
- Create, update, and delete are hidden globally.
- Generic `execute_entity` is hidden globally. Approved stored procedures are exposed only as individually named custom tools.
- A tool must also be allowed by its entity permissions and by the prompt agent's `allowed_tools` list.

### Explicitly expose approved entities

Keep `autoentities` empty. Do not use wildcard discovery for the customer contract because it can expose newly created database objects without review.

Each approved view has:

- A stable DAB entity name.
- The exact `dbo.<view>` source and source type `view`.
- A semantic entity description.
- Explicit field names and descriptions so agents don't guess SQL column names.
- One stable field marked `primary-key` for DAB query/pagination behavior.
- Read-only permissions.
- `mcp.dml-tools=true` and `mcp.custom-tool=false`.

Representative view configuration:

```json
{
  "entities": {
    "TransferSummary": {
      "description": "Read-only transfer status, client, account, advisor, amount, dates, priority, and age.",
      "source": {
        "object": "dbo.vw_transfer_summary",
        "type": "view"
      },
      "fields": [
        {
          "name": "TransferId",
          "description": "Stable numeric transfer identifier",
          "primary-key": true
        },
        {
          "name": "ClientCode",
          "description": "Exact synthetic client identifier"
        }
      ],
      "permissions": [
        { "role": "Mcp.Invoke", "actions": [{ "action": "read" }] },
        { "role": "authenticated", "actions": [{ "action": "read" }] }
      ],
      "mcp": {
        "dml-tools": true,
        "custom-tool": false
      }
    }
  }
}
```

The committed configuration exposes only:

| DAB entity | SQL source | MCP behavior |
|---|---|---|
| `TransferSummary` | `dbo.vw_transfer_summary` | Read and aggregate |
| `ClientAccountOverview` | `dbo.vw_client_account_overview` | Read and aggregate |
| `TransferRiskDashboard` | `dbo.vw_transfer_risk_dashboard` | Read and aggregate |
| `AdvisorPipeline` | `dbo.vw_advisor_pipeline` | Read and aggregate |

### Configure stored procedures as named custom tools

Each approved stored procedure is an explicit entity with typed parameters, `execute` permission, `custom-tool=true`, and generic DML tools disabled:

```json
{
  "entities": {
    "GetTransferSummaryByClient": {
      "description": "Return all transfer summaries for one exact client code such as CLIENT-001.",
      "source": {
        "object": "dbo.usp_GetTransferSummaryByClient",
        "type": "stored-procedure",
        "parameters": [
          {
            "name": "ClientCode",
            "description": "Exact client code",
            "required": true
          }
        ]
      },
      "permissions": [
        { "role": "Mcp.Invoke", "actions": [{ "action": "execute" }] },
        { "role": "authenticated", "actions": [{ "action": "execute" }] }
      ],
      "mcp": {
        "custom-tool": true,
        "dml-tools": false
      }
    }
  }
}
```

The resulting named tools are:

| MCP custom tool | SQL procedure |
|---|---|
| `get_transfer_summary_by_client` | `dbo.usp_GetTransferSummaryByClient` |
| `get_open_risk_alerts` | `dbo.usp_GetOpenRiskAlerts` |
| `get_advisor_pipeline` | `dbo.usp_GetAdvisorPipeline` |

Do not expose a stored procedure merely because it exists. It must be reviewed, granted to `mcp_reader`, configured as a DAB entity, and added to the agent allowlist.

### Understand the two DAB roles

The MCP enterprise application requires an explicit `Mcp.Invoke` assignment before Entra issues an application token. DAB includes identical read/execute-only permissions for `Mcp.Invoke` and its system `authenticated` role because role selection differs by request surface. Neither role grants create, update, delete, raw-table access, or arbitrary SQL. The database-level `mcp_reader` role remains the final authorization boundary.

For a customer deployment, change role names only after validating the actual token claims and whether the client sends `X-MS-API-ROLE`. Never broaden an entity to `anonymous` to fix a role-selection problem.

### Validate before building

Run the repository's aggregate validation:

```powershell
./scripts/test-demo.ps1
```

It parses `dab-config.json`, validates it against DAB 2.0.9, confirms all entities have only the expected roles/actions, verifies write and generic-execute tools are disabled, and checks the pinned image version. For a focused schema check:

```powershell
$env:DATABASE_CONNECTION_STRING = 'Server=tcp:demo.invalid,1433;Initial Catalog=TransferDemo;Authentication=Active Directory Managed Identity;User Id=00000000-0000-0000-0000-000000000000;Encrypt=True;TrustServerCertificate=False;'
dab validate --config ./src/mcp-server/dab-config.json
```

The expected result contains `The config satisfies the schema requirements`. This validation checks configuration shape; live startup still validates database connectivity and object metadata.

### Build the pinned image

The portal does not turn repository source into the validated DAB image. Build it through ACR Tasks:

```powershell
./scripts/build-demo-mcp.ps1 `
  -RegistryName $values.AZURE_CONTAINER_REGISTRY_NAME `
  -McpApplicationId $values.MCP_AUTH_APP_ID `
  -TenantId $values.AZURE_TENANT_ID
```

The build:

- Pins `mcr.microsoft.com/azure-databases/data-api-builder:2.0.9`.
- Replaces the committed placeholder with the bare MCP application client ID.
- Tags the image with a hash of the generated configuration and Dockerfile, so documentation-only commits don't rebuild the runtime.
- Stores the resulting image URI in `MCP_CONTAINER_IMAGE`.

The currently validated content-addressed image is `acrsqlmcpdemobtqgzq.azurecr.io/sql-mcp:2.0.9-cac6d92b9c31`, digest `sha256:4e72f84201e50f8c3c07729811b67e98773b48813db946c1db820a5d7350a77b`.

## 10. Deploy the SQL contract and identity

**What it is:** The SQL contract is the database-side security and semantic layer: synthetic tables, curated views, parameterized procedures, `mcp_reader`, and the MCP UAMI contained user.

**Why it is needed:** DAB permissions can't grant access SQL itself denies. Named-object SQL grants provide defense in depth and prevent raw-table or write access even if an API permission is broadened accidentally.

**How to configure it:**

Install modern sqlcmd once:

```powershell
winget install --id Microsoft.Sqlcmd
```

Apply the idempotent schema, deterministic synthetic data, approved views/procedures, and least-privilege SQL grants:

```powershell
$values = azd env get-values --output json | ConvertFrom-Json
./scripts/deploy-demo-database.ps1 `
  -Server "$($values.AZURE_SQL_SERVER_FQDN),1433" `
  -DatabaseName $values.AZURE_SQL_DATABASE_NAME `
  -McpIdentityName $values.AZURE_MCP_IDENTITY_NAME `
  -McpIdentityClientId $values.AZURE_MCP_IDENTITY_CLIENT_ID
```

Azure SQL Database creates the MCP contained user from the UAMI client-ID SID and `TYPE = E`; it does not need SQL MI's Directory Readers prerequisite. Confirm in the database that:

- `mcp_reader` has `SELECT` only on four approved views.
- `mcp_reader` has `EXECUTE` only on three approved stored procedures.
- The MCP identity belongs only to `mcp_reader`.
- Raw tables and writes remain denied.

## 11. Create the SQL MCP Container App

**What it is:** This is the running instance of the configured DAB image, with an external HTTPS endpoint and the MCP UAMI attached.

**Why it is needed:** Foundry requires a remote HTTP MCP endpoint. The app also supplies the managed-identity SQL connection string and pulls the pinned image from ACR.

**How to configure it:**

In **Azure portal > Container Apps > Create**:

1. Select the existing public environment in East US 2.
2. Name the app `app-sql-mcp-demo-<suffix>`.
3. Assign user identity `id-mcp-foundry-sql-mcp-demo`.
4. Select the ACR image produced in the previous step.
5. Configure ACR authentication with the same user-assigned identity.
6. Set CPU to `0.5`, memory to `1 GiB`, minimum replicas to `1`, and maximum replicas to `1`.
7. Enable external HTTPS ingress on target port `5000`; do not allow insecure HTTP.
8. Add environment variable `DAB_ENVIRONMENT=Production`.
9. Add non-secret environment variable `DATABASE_CONNECTION_STRING`:

```text
Server=tcp:<sql-server>.database.windows.net,1433;Initial Catalog=TransferDemo;Authentication=Active Directory Managed Identity;User Id=<mcp-uami-client-id>;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;
```

10. Deploy and wait for the revision to become healthy.

Do not add SQL passwords, registry passwords, or secrets to the Container App.

## 12. Create the Foundry MCP project connection

**What it is:** A RemoteTool project connection stores the MCP endpoint, audience, and selected Foundry identity authentication mode.

**Why it is needed:** The agent definition references a connection by name. Agent Service uses it to acquire a token from the project identity and attach that token when calling `/mcp`.

**How to configure it:**

In **Microsoft Foundry portal > project > Build > Tools**:

1. Select **Connect a tool > Custom > MCP**. Portal wording can vary while the preview evolves.
2. Name the connection `sql-mcp-demo`.
3. Set the endpoint to `https://<container-app-fqdn>/mcp`.
4. Select **Microsoft Entra - project managed identity** authentication.
5. Set audience to `api://<mcp-application-client-id>`.
6. Share the connection with the project if prompted.

After creation, inspect the connection JSON or Azure resource JSON and confirm:

```text
category: RemoteTool
authType: ProjectManagedIdentity
useWorkspaceManagedIdentity: true
audience: api://<mcp-application-client-id>
target: https://<container-app-fqdn>/mcp
```

If the portal doesn't expose `useWorkspaceManagedIdentity`, run `azd provision --no-prompt` to reconcile the exact Bicep contract.

## 13. Register the prompt agent

**What it is:** A prompt agent is an immutable Foundry version containing the model, behavioral instructions, MCP connection reference, tool allowlist, and approval policy.

**Why it is needed:** DAB exposes capabilities, but the agent governs when and how those capabilities are selected and how tool results are presented without inventing data.

**How to configure it:**

The project-native prompt agent is versioned through the Foundry v2 SDK so its immutable definition is reproducible:

```powershell
./scripts/register-demo-agent.ps1
./scripts/test-demo-agent.ps1
```

The agent uses `gpt-5.4-mini`, connection `sql-mcp-demo`, and only these tools:

- `describe_entities`
- `read_records`
- `aggregate_records`
- `get_transfer_summary_by_client`
- `get_open_risk_alerts`
- `get_advisor_pipeline`

The three report intents are routed to their custom tools. All tools are read-only, so approval is set to `never`. The currently validated agent is `transfer-agent-sql-mcp-demo:2`.

## 14. Validate in the portals

**What it is:** Validation checks the deployed control plane, identities, network rules, runtime health, and agent behavior as one system.

**Why it is needed:** A successful ARM deployment doesn't prove SQL connectivity, JWT claims, DAB permissions, or deterministic tool routing. The demo isn't complete until those paths and negative controls pass.

**How to validate it:**

In **Azure portal**:

1. Confirm Azure SQL Database is `Online`, Entra-only, TLS 1.2, and `SecuredByPerimeter`.
2. Confirm the NSP association is `Enforced` and has only the subscription and operator rules.
3. Confirm the MCP UAMI has only `AcrPull` in Azure RBAC.
4. Confirm the Container App has one healthy replica and the expected commit-tagged image.
5. Confirm no temporary diagnostic Container App or image repository remains.

In **Microsoft Entra admin center**:

1. Confirm the MCP enterprise application requires assignment.
2. Confirm the Foundry project identity has only the `Mcp.Invoke` app-role assignment on that application.

In **Microsoft Foundry portal > Build > Agents**:

1. Select `transfer-agent-sql-mcp-demo`, latest version.
2. Open **Playground**.
3. Run:

```text
Return the transfer summary for CLIENT-001.
Show open High severity risk alerts.
Summarize the transfer pipeline for advisor ADV-MIL-01.
```

Each response must contain grounded synthetic SQL rows. Anonymous MCP/data calls must fail, wrong-audience tokens must fail, and raw tables/write operations must remain unavailable.

## 15. Cleanup

**What it is:** Cleanup removes the disposable demo resource group and MCP Entra application while preserving the private customer-reference environment.

**Why it is needed:** Public evaluation endpoints and paid resources are time-bounded exceptions, not durable production defaults.

**How to perform it:**

The supported cleanup path removes the disposable resource group and MCP Entra application without touching the private SQL MI environment:

```powershell
./scripts/cleanup-demo.ps1 -ConfirmCleanup
```

After cleanup, verify that `rg-foundry-sql-mcp-demo` and `foundry-sql-mcp-demo-api` no longer exist. Do not delete or modify `rg-foundry-sql-mcp-dev-centralus`.

## Repository-supported path

The portal steps explain every resource and security decision. For repeatable recreation, Bicep remains authoritative:

```powershell
azd up --environment foundry-sql-mcp-demo
```

The command is intentionally idempotent. Its hooks validate prerequisites, reconcile both infrastructure phases, reuse unchanged image and agent artifacts, rerun deterministic SQL migrations, restore the prior NSP rule in `finally`, and execute end-to-end smoke tests. Use `azd provision --preview --no-prompt` separately when you need a control-plane preview without running data-plane setup.

See [SQL MCP Public Demo Guide](demo-guide.md) for the concise operator sequence and [SQL Backend Options](sql-backend-options.md) for customer SQL MI and on-premises SQL Server requirements.