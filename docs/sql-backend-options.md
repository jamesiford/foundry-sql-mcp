# SQL Backend Options for SQL MCP Server

SQL MCP Server is a Data API builder 2.x feature. DAB uses the `mssql` provider for Azure SQL Database, Azure SQL Managed Instance, and SQL Server 2016 or later. The MCP entity/tool configuration can remain the same across these backends; networking, identity bootstrap, and connection strings differ.

## Decision matrix

| Backend | DAB support | Preferred MCP placement | Preferred authentication | Main prerequisite |
|---|---|---|---|---|
| Azure SQL Database | Supported | Public or private Azure Container Apps | UAMI with Entra contained user | Create user by client-ID SID or external-provider lookup |
| Azure SQL Managed Instance | Supported | VNet-integrated/private Container Apps | UAMI with Entra user/login | SQL MI server identity must have Entra Directory Readers |
| On-premises SQL Server 2022 with Azure Arc | Supported | On-prem/DMZ container or Azure over VPN/ExpressRoute | Entra service principal/OBO where validated | Arc-enabled Entra authentication and hybrid network path |
| On-premises SQL Server 2016-2019 or non-Arc | Supported | Prefer DAB near the database | Windows or SQL authentication | Approved secret/credential lifecycle and network path |

## Azure SQL Database demo pattern

The public evaluation branch uses a disposable Azure SQL Database because it provides the shortest passwordless path:

- Logical-server endpoint on TCP `1433` with `SecuredByPerimeter`.
- Microsoft Entra-only server authentication.
- Enforced Network Security Perimeter profile with a demo-subscription rule for Container Apps and exact deployment-client source rules; no VNet or private endpoint.
- DAB Container App UAMI authenticates with `Active Directory Managed Identity`.
- The contained application user is created without Graph lookup:

```sql
CREATE USER [id-mcp-foundry-sql-mcp-demo]
WITH SID = <mcp-uami-client-id-as-varbinary-16>, TYPE = E;
```

`TYPE = E`/direct SID creation is supported by Azure SQL Database. It avoids granting Microsoft Graph directory permissions to the logical-server identity.

The current subscription has a management-group policy that modifies ordinary SQL public network access to `Disabled`. The demo therefore uses Network Security Perimeter rather than bypassing policy with an older API or requesting a broad firewall exemption. This is a demo constraint, not the recommended customer SQL MI topology.

## Azure SQL Managed Instance customer pattern

SQL MI is the expected customer backend and remains the secure architecture on `main`.

### Network requirements

- SQL MI always requires its delegated VNet/subnet.
- Preferred path: internal DAB/SQL MCP Container App in the same or peered VNet, using the SQL MI private FQDN on TCP `1433`.
- Foundry reaches a private MCP endpoint through Standard Agent Setup with private networking.
- Avoid enabling SQL MI public endpoint TCP `3342` for production MCP traffic.

### Identity requirements

1. Give SQL MI a primary system- or user-assigned managed identity.
2. Assign the SQL MI server identity the Microsoft Entra **Directory Readers** directory role. SQL MI does not support Azure SQL Database's direct `SID`/`TYPE = E` user creation path.
3. A Privileged Role Administrator or Global Administrator must grant Directory Readers in Microsoft Entra. This is not an Azure resource IAM assignment.
4. Connect as the SQL MI Entra administrator and create the MCP identity:

```sql
CREATE USER [<mcp-managed-identity-name>] FROM EXTERNAL PROVIDER;
ALTER ROLE [mcp_reader] ADD MEMBER [<mcp-managed-identity-name>];
```

5. Grant only named views/procedures through `mcp_reader`; never use `db_datareader`, `db_datawriter`, or `db_owner`.

Directory Readers is broader than the SQL data permissions. It lets the SQL engine resolve Entra principals; it does not grant database access to those principals. Database access still requires explicit user/login creation and SQL grants.

### Customer readiness checklist

- Tenant administrator approves SQL MI Directory Readers for the server identity.
- Network team provides private routing and DNS between MCP hosting and SQL MI.
- Database team creates approved views/procedures and custom role grants.
- MCP team validates managed-identity connection, raw-table denial, and write denial.
- Foundry team validates private MCP reachability and agent identity/audience.

## On-premises SQL Server pattern

Yes, on-premises SQL Server is supported. DAB supports SQL Server 2016 and later and can run in Azure or on-premises.

### Hosting choices

**DAB hosted near SQL Server** is usually simplest:

- Run the pinned DAB container on on-premises Kubernetes, a container host, or a DMZ host.
- Publish only the Entra-authenticated MCP endpoint through an approved reverse proxy/API gateway.
- Foundry calls the remote HTTPS MCP endpoint; the database never needs inbound internet exposure.

**DAB hosted in Azure** requires private hybrid networking:

- Put Container Apps/AKS/App Service into a VNet.
- Connect the VNet to on-premises with site-to-site VPN or ExpressRoute.
- Configure private DNS/name resolution, routes, firewall rules, and TCP `1433` or the customer's SQL port.
- Do not expose the on-premises SQL listener publicly for the agent.

### Authentication choices

- SQL Server 2022 enabled by Azure Arc can use Microsoft Entra authentication. Validate the exact service-principal/managed-identity token flow and database audience in the customer's tenant before selecting it.
- DAB 2.x also supports OBO for `mssql` when per-user SQL authorization is required. This needs an Entra application, downstream SQL token exchange, and separate per-user connection pools.
- For SQL Server 2016-2019 or non-Arc environments, use the customer's approved Windows-integrated or SQL authentication design. Store credentials in Key Vault or the enterprise secret platform, rotate them, and never commit them to DAB config or source control.

### On-premises security checklist

- Keep DAB's entity allowlist and SQL custom roles even if network access is private.
- Use TLS and validate the SQL Server certificate; do not set `TrustServerCertificate=True` in production.
- Put an API gateway/reverse proxy in front of public MCP endpoints for JWT validation, rate limiting, and logging.
- Decide explicitly whether calls use one application identity or OBO user identity.
- Test failure behavior when VPN/ExpressRoute or on-prem SQL is unavailable.

## Portable artifacts

These repository artifacts are backend-portable:

- `src/data/sql/001_schema.sql` through `003_contract.sql`.
- `mcp_reader` named-object grants.
- `src/mcp-server/dab-config.json` entity descriptions, permissions, and tool allowlist.
- Prompt-agent instructions and evaluation prompts.

Backend-specific deployment automation should supply the connection string and create the workload identity/user appropriate to that SQL platform.

## Microsoft references

- [DAB data source configuration](https://learn.microsoft.com/azure/data-api-builder/configuration/data-source)
- [Microsoft Entra service principals with Azure SQL](https://learn.microsoft.com/azure/azure-sql/database/authentication-aad-service-principal)
- [Configure Microsoft Entra authentication for SQL MI](https://learn.microsoft.com/azure/azure-sql/database/authentication-aad-configure)
- [Microsoft Entra authentication for SQL Server enabled by Azure Arc](https://learn.microsoft.com/sql/sql-server/azure-arc/microsoft-entra-authentication-overview)
- [Hybrid networking with VPN and ExpressRoute](https://learn.microsoft.com/azure/architecture/hybrid/hybrid-start-here)