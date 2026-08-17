# Synthetic Data and the SQL Contract

Idempotent SQL migrations that build the demo database: schema, deterministic synthetic data, the
approved views and stored procedures the agent may reach, and the least-privilege grants that
enforce it.

> All records are synthetic. No customer or production data belongs in this directory.

## Migrations

Applied in order by `scripts/deploy-demo-database.ps1`:

| Script | Purpose |
|---|---|
| `000_create_database.sql` | Creates the database (bootstrap path only) |
| `001_schema.sql` | Base tables — **never exposed to the agent** |
| `002_seed.sql` | Deterministic synthetic data, so runs are reproducible |
| `003_contract.sql` | The four approved views and three approved stored procedures |
| `004_security.sql` | `mcp_reader` role, named-object grants, MCP identity user |

```powershell
$values = azd env get-values --output json | ConvertFrom-Json
./scripts/deploy-demo-database.ps1 `
  -Server "$($values.AZURE_SQL_SERVER_FQDN),1433" `
  -DatabaseName $values.AZURE_SQL_DATABASE_NAME `
  -McpIdentityName $values.AZURE_MCP_IDENTITY_NAME `
  -McpIdentityClientId $values.AZURE_MCP_IDENTITY_CLIENT_ID
```

## The contract

`003_contract.sql` is the semantic boundary. Base tables are never published; the agent sees only
these views, which pre-join and pre-filter so no client has to:

| Object | Type |
|---|---|
| `dbo.vw_transfer_summary` | view |
| `dbo.vw_client_account_overview` | view |
| `dbo.vw_transfer_risk_dashboard` | view |
| `dbo.vw_advisor_pipeline` | view |
| `dbo.usp_GetTransferSummaryByClient` | stored procedure |
| `dbo.usp_GetOpenRiskAlerts` | stored procedure |
| `dbo.usp_GetAdvisorPipeline` | stored procedure |

A view is also a practical requirement, not only a security one: the `read_records` MCP tool
operates on a single table or view and does not support JOINs. Any question needing a join needs a
view.

## Security

`004_security.sql` creates `mcp_reader` and grants `SELECT` on the four views and `EXECUTE` on the
three procedures — **named objects only**. Never `db_datareader`, `db_datawriter`, or `db_owner`.

This is the authoritative boundary. DAB permissions narrow the surface further but cannot grant what
SQL denies. Apply SQL before configuration: publishing an entity SQL has not granted produces a tool
that lists cleanly and fails only when invoked.

## Identity — Azure SQL Database vs SQL Managed Instance

`004_security.sql` creates the MCP identity with `CREATE USER ... WITH SID = ..., TYPE = E`. This is
**Azure SQL Database only**. It creates a contained user directly from the identity's client ID and
avoids granting directory permissions to the logical server.

**SQL Managed Instance does not support this syntax.** On SQL MI:

```sql
CREATE USER [<mcp-uami-name>] FROM EXTERNAL PROVIDER;
ALTER ROLE [mcp_reader] ADD MEMBER [<mcp-uami-name>];
```

This requires the SQL MI server identity to hold the Entra **Directory Readers** role, granted by a
Privileged Role Administrator or Global Administrator. It is a directory role, not an Azure resource
role, and usually follows a slower approval path.

If a view reads across databases, a contained user is insufficient — the caller cannot be resolved
in the second database. SQL MI supports server-level Entra logins for this case. See
[SQL Backend Options](../../docs/sql-backend-options.md#azure-sql-managed-instance-customer-pattern).

## Adapting this to your own data

These scripts build a synthetic demo. For guidance on selecting and modelling your own objects, see
[Configuring SQL MCP Server for your own databases](../../docs/configure-for-your-database.md).
