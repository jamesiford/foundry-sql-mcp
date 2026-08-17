# Configuring SQL MCP Server for your own databases

Step 9 of the [portal runbook](demo-portal-runbook.md) shows a finished configuration for the demo's
synthetic database. This guide covers the part that runbook does not: **how to decide what your own
agent should be able to see, and how to express that in configuration.**

It assumes no prior exposure to Data API builder or MCP. Everything is illustrated with a worked
example — a commercial lending database, built from base tables through to a working agent.

**Applies to** Data API builder 2.0.9 · SQL MCP Server · Azure SQL Database and Azure SQL Managed Instance

---

## 1. What this document is for

Step 9 of the runbook says "configure and build SQL MCP Server" and then shows you a finished configuration file for a demo database. That is fine if you are running the demo. It is not much help when the database is your own.

This guide fills that gap. It explains **how to decide what your agent should be able to see**, and then how to express that decision in configuration. It assumes no prior exposure to Data API builder or MCP.

Everything is illustrated with a worked example — a commercial lending database, built out from base tables through to a working agent. The names are invented, but the shape is deliberately close to what you already have, so you can substitute your own objects step by step.

**Read sections 2 and 3 before you touch any configuration.** They cover the two decisions that determine whether this works well or badly, and both are much cheaper to get right at the start than to correct later.

---

## 2. The mental model

Four layers sit between a user's question and a row of your data. Each one can say no, and understanding which is which will save you hours of diagnosis.

| # | Layer | What it controls | Who owns it |
| --- | --- | --- | --- |
| 1 | **SQL objects** | What exists — tables, views, procedures | Your DBA / data owners |
| 2 | **SQL permissions** | What the MCP identity is allowed to read | Your DBA |
| 3 | **DAB configuration** | What is *published* to the agent, and how it is described | You, in `dab-config.json` |
| 4 | **Agent tool allowlist** | Which published tools the agent may actually call | You, in the agent definition |

Two rules follow, and both matter.

**SQL is the final authority.** If `mcp_reader` cannot select from an object, no amount of configuration will make it readable. This is deliberate — the database is the last line of defence, and it does not trust the API layer.

**Always apply SQL before configuration.** If you publish an entity that SQL has not granted, the tool appears in the agent's list and fails only when invoked — a confusing failure a long way from its cause. If you grant in SQL but do not publish, nothing happens at all, which is a safe and obvious state.

### 2.1 How the agent actually sees your data

The agent does not read your schema. It calls a tool called `describe_entities`, which returns **only what you wrote in the configuration file** — entity names, entity descriptions, field names, field descriptions.

This is the single most important thing to understand in this document. Microsoft's own documentation puts it bluntly:

> *"Without field names and descriptions, agents see only entity names and may guess column names incorrectly."*

If you publish a view with no field descriptions, the agent is guessing. It will guess plausibly and confidently, and it will be wrong in ways that are hard to spot. **Descriptions are not documentation. They are the interface.**

---

## 3. Decide what to expose — before you configure anything

### 3.1 Expose views, not base tables

You *can* publish a base table. You should not.

| | Base table | Curated view |
| --- | --- | --- |
| Columns exposed | All of them, including anything added later | Only what you chose |
| Sensitive fields | Present unless you exclude each one | Never selected in the first place |
| Business logic | None — the agent must infer joins and filters | Baked in, applied consistently |
| New column added upstream | Silently exposed | Not exposed until someone edits the view |
| Renaming or refactoring | Breaks the agent | Absorbed by the view |

A view is a contract. It is the place where you decide, once, what "a loan" means for the purposes of the agent — and it is reviewable by the people who own that answer.

There is also a practical reason. The `read_records` tool works against **a single table or view and does not support JOINs.** Microsoft's guidance is explicit:

> *"The `read_records` tool is designed for a single table or view. As a result, JOIN operations aren't supported... For more complex queries, we recommend using a view instead of a table."*

If the answer to a question requires joining three tables, the join belongs in a view. The agent cannot do it for you.

### 3.2 Put the views in their own schema

Create a dedicated SQL schema — call it `mcp` — and put every agent-visible view and procedure in it. Nothing else goes there.

This is worth the small amount of effort because it converts a sprawling permissions question into a simple one. "What can the agent see?" becomes "what is in the `mcp` schema?" — a question your data owners can answer by looking, and a boundary your security reviewers can verify in one query.

It also makes the eventual scale-up cleaner. If you later move to pattern-based publishing (section 10), a dedicated schema is what makes the pattern safe.

### 3.3 Start with three to five views

The instinct is to expose everything so the agent can answer anything. Resist it.

More entities makes answers **worse**, not better. Every published entity consumes room in the model's context, and every one without good field descriptions is another opportunity to guess wrong. A tight set of well-described views will outperform a large set of thinly-described ones — consistently, and by a wide margin.

Choose your first views by working backwards from real questions. Ask your business stakeholders for **ten to fifteen questions they would actually put to this agent**, then pick the smallest set of views that answers them. That list also becomes your test set in section 9.

### 3.4 Keep each view inside one database

This one is specific to your environment and worth stating plainly, because it is what blocked you last week.

A view that reads across databases requires the caller to be resolvable in every database it touches. That works, but it needs a server-level Entra login rather than a contained database user, plus a mapped user in each database. It is more moving parts, and more places for a permission to be missing.

Where you have the choice, **keep each agent-facing view inside a single database.** Where the business logic genuinely spans databases, that is a legitimate reason to cross the boundary — just do it deliberately, and see section 8 for the identity setup it requires.

---

## 4. The worked example

Everything from here uses one illustrative database. Substitute your own objects as you go.

### 4.1 Starting point — the base tables

Assume a `LendingOps` database with a conventional commercial lending schema. **None of these will be exposed to the agent.**

```sql
-- Existing base tables in the LendingOps database. Illustrative.
dbo.Borrower          -- BorrowerId, LegalName, TaxId, RelationshipManagerId, Industry, ...
dbo.Loan              -- LoanId, LoanNumber, BorrowerId, OriginationDate, MaturityDate,
                      -- CommittedAmount, OutstandingBalance, InterestRate, StatusCode, ...
dbo.Facility          -- FacilityId, LoanId, FacilityType, LimitAmount, ...
dbo.PaymentSchedule   -- ScheduleId, LoanId, DueDate, AmountDue, AmountPaid, PaidDate, ...
dbo.RiskRating        -- RatingId, BorrowerId, RatingCode, RatingDate, AnalystId, ...
dbo.RelationshipMgr   -- RelationshipManagerId, FullName, Region, ...
```

Note `dbo.Borrower.TaxId`. It is exactly the kind of column that must never reach an agent, and the reason we never publish base tables.

### 4.2 The questions we want answered

From an imagined stakeholder session:

1. What is the outstanding balance on loan `CL-2024-0187`?
2. Which loans mature in the next 90 days?
3. What is our total committed exposure to a given borrower?
4. Which loans are more than 30 days delinquent?
5. How many loans does each relationship manager hold, and what is the total balance?
6. Which borrowers in Manufacturing have a risk rating worse than 5?

Six questions. They need **three views and one stored procedure** — not access to six tables.

### 4.3 Create the schema

```sql
USE [LendingOps];
GO

IF SCHEMA_ID(N'mcp') IS NULL
    EXEC(N'CREATE SCHEMA mcp AUTHORIZATION dbo;');
GO
```

### 4.4 Build the curated views

**View 1 — loan summary.** Answers questions 1, 2 and 5. Joins three tables so the agent never has to.

```sql
CREATE OR ALTER VIEW mcp.vw_loan_summary
AS
SELECT
    l.LoanId,
    l.LoanNumber,
    b.BorrowerId,
    b.LegalName            AS BorrowerName,
    b.Industry,
    rm.FullName            AS RelationshipManager,
    rm.Region,
    l.OriginationDate,
    l.MaturityDate,
    l.CommittedAmount,
    l.OutstandingBalance,
    l.InterestRate,
    l.StatusCode           AS LoanStatus,
    DATEDIFF(DAY, GETUTCDATE(), l.MaturityDate) AS DaysToMaturity
FROM dbo.Loan AS l
INNER JOIN dbo.Borrower AS b
    ON b.BorrowerId = l.BorrowerId
LEFT JOIN dbo.RelationshipMgr AS rm
    ON rm.RelationshipManagerId = b.RelationshipManagerId
WHERE l.StatusCode <> 'DELETED';
GO
```

Note what is **not** there: no `TaxId`, no internal analyst identifiers, no soft-deleted rows. Those exclusions are the contract.

**View 2 — borrower exposure.** Answers question 3, pre-aggregated.

```sql
CREATE OR ALTER VIEW mcp.vw_borrower_exposure
AS
SELECT
    b.BorrowerId,
    b.LegalName            AS BorrowerName,
    b.Industry,
    rm.FullName            AS RelationshipManager,
    COUNT(l.LoanId)        AS LoanCount,
    SUM(l.CommittedAmount) AS TotalCommitted,
    SUM(l.OutstandingBalance) AS TotalOutstanding,
    MAX(r.RatingCode)      AS CurrentRiskRating
FROM dbo.Borrower AS b
LEFT JOIN dbo.Loan AS l
    ON l.BorrowerId = b.BorrowerId AND l.StatusCode = 'ACTIVE'
LEFT JOIN dbo.RelationshipMgr AS rm
    ON rm.RelationshipManagerId = b.RelationshipManagerId
OUTER APPLY (
    SELECT TOP 1 rr.RatingCode
    FROM dbo.RiskRating AS rr
    WHERE rr.BorrowerId = b.BorrowerId
    ORDER BY rr.RatingDate DESC
) AS r
GROUP BY b.BorrowerId, b.LegalName, b.Industry, rm.FullName;
GO
```

**View 3 — delinquency watchlist.** Answers question 4.

```sql
CREATE OR ALTER VIEW mcp.vw_delinquency_watchlist
AS
SELECT
    l.LoanId,
    l.LoanNumber,
    b.LegalName            AS BorrowerName,
    rm.FullName            AS RelationshipManager,
    ps.DueDate             AS OldestUnpaidDueDate,
    DATEDIFF(DAY, ps.DueDate, GETUTCDATE()) AS DaysPastDue,
    ps.AmountDue           AS AmountPastDue,
    l.OutstandingBalance
FROM dbo.Loan AS l
INNER JOIN dbo.Borrower AS b
    ON b.BorrowerId = l.BorrowerId
LEFT JOIN dbo.RelationshipMgr AS rm
    ON rm.RelationshipManagerId = b.RelationshipManagerId
CROSS APPLY (
    SELECT TOP 1 p.DueDate, p.AmountDue
    FROM dbo.PaymentSchedule AS p
    WHERE p.LoanId = l.LoanId
      AND p.PaidDate IS NULL
      AND p.DueDate < GETUTCDATE()
    ORDER BY p.DueDate ASC
) AS ps
WHERE l.StatusCode = 'ACTIVE';
GO
```

### 4.5 Add a stored procedure

Question 1 asks for one specific loan by number. A view plus a filter would work, but a purpose-built procedure is better for the intents your users hit constantly: the agent sees a named tool, the parameter is explicit, and the SQL is fixed.

```sql
CREATE OR ALTER PROCEDURE mcp.usp_GetLoanByNumber
    @LoanNumber VARCHAR(32)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        LoanId, LoanNumber, BorrowerName, Industry,
        RelationshipManager, OriginationDate, MaturityDate,
        CommittedAmount, OutstandingBalance, InterestRate,
        LoanStatus, DaysToMaturity
    FROM mcp.vw_loan_summary
    WHERE LoanNumber = @LoanNumber;
END;
GO
```

Note it selects from the view, not the base tables. One definition of "a loan", reused.

### 4.6 Grant — least privilege

```sql
USE [LendingOps];
GO

-- 1. A role that carries the grants
IF DATABASE_PRINCIPAL_ID(N'mcp_reader') IS NULL
    CREATE ROLE [mcp_reader] AUTHORIZATION [dbo];
GO

-- 2. Grant on named objects only. Never db_datareader.
GRANT SELECT  ON OBJECT::mcp.vw_loan_summary          TO [mcp_reader];
GRANT SELECT  ON OBJECT::mcp.vw_borrower_exposure     TO [mcp_reader];
GRANT SELECT  ON OBJECT::mcp.vw_delinquency_watchlist TO [mcp_reader];
GRANT EXECUTE ON OBJECT::mcp.usp_GetLoanByNumber      TO [mcp_reader];
GO

-- 3. Add the MCP managed identity to the role
ALTER ROLE [mcp_reader] ADD MEMBER [<mcp-uami-name>];
GO
```

**Never grant `db_datareader`.** It grants SELECT on everything, including `dbo.Borrower.TaxId`, and silently includes every table added in future. Named-object grants are the whole point.

### 4.7 Verify before configuring

Prove the grants are right before writing any JSON. Run as the MCP identity if you can, or inspect the grants directly:

```sql
-- What can mcp_reader actually reach?
SELECT
    dp.name          AS principal_name,
    o.name           AS object_name,
    s.name           AS schema_name,
    p.permission_name,
    p.state_desc
FROM sys.database_permissions AS p
JOIN sys.database_principals  AS dp ON dp.principal_id = p.grantee_principal_id
JOIN sys.objects              AS o  ON o.object_id = p.major_id
JOIN sys.schemas              AS s  ON s.schema_id = o.schema_id
WHERE dp.name = N'mcp_reader'
ORDER BY s.name, o.name;

-- Confirm the identity is in the role
SELECT rp.name AS role_name, mp.name AS member_name
FROM sys.database_role_members AS drm
JOIN sys.database_principals   AS rp ON rp.principal_id = drm.role_principal_id
JOIN sys.database_principals   AS mp ON mp.principal_id = drm.member_principal_id
WHERE rp.name = N'mcp_reader';
```

Expect exactly four objects and one member. Anything else is a finding.

---

## 5. The tool surface

Before configuring, understand what you are switching on. SQL MCP Server exposes **seven DML tools**. All are enabled by default.

| Tool | What it does | For a read-only agent |
| --- | --- | --- |
| `describe_entities` | Lists entities, fields, descriptions | **Enable** — the agent's map |
| `read_records` | Query a single view or table | **Enable** |
| `aggregate_records` | count, sum, avg, min, max, group by, having | **Enable** |
| `create_record` | Insert | **Disable** |
| `update_record` | Update | **Disable** |
| `delete_record` | Delete | **Disable** |
| `execute_entity` | Run *any* permitted stored procedure | **Disable** — see below |

Two notes worth understanding.

**Why disable `execute_entity` even though you want procedures.** It is a generic tool: the agent supplies a procedure name. Named custom tools (section 7) are better — each procedure appears under its own name with its own description, and the agent cannot reach for something you did not intend. Disable the generic tool, publish specific ones.

**Defence in depth.** Disabling a tool globally hides it completely, regardless of any entity's permissions. That is a blunt, reliable control. Entity permissions and SQL grants still apply underneath. Use all three.

---

## 6. Configure the runtime

Now the configuration file. This section sets global behaviour.

```json
{
  "$schema": "https://github.com/Azure/data-api-builder/releases/download/v2.0.9/dab.draft.schema.json",
  "data-source": {
    "database-type": "mssql",
    "connection-string": "@env('DATABASE_CONNECTION_STRING')",
    "options": { "set-session-context": false }
  },
  "runtime": {
    "rest":    { "enabled": false },
    "graphql": { "enabled": false },
    "mcp": {
      "enabled": true,
      "path": "/mcp",
      "dml-tools": {
        "describe-entities": true,
        "read-records": true,
        "aggregate-records": { "enabled": true, "query-timeout": 30 },
        "create-record": false,
        "update-record": false,
        "delete-record": false,
        "execute-entity": false
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
  },
  "autoentities": {},
  "entities": { }
}
```

Points that matter:

- **Never put a credential in `connection-string`.** `@env(...)` reads it from the Container App at runtime, and the connection uses managed identity.
- **The audience and issuer are build-time placeholders.** The build script substitutes your real MCP application client ID and tenant ID. Verify that substitution happened — a mismatch surfaces as a `401` much later, far from its cause.
- **REST and GraphQL are switched off.** The agent uses MCP. Every other surface is attack surface.
- **`"mode": "production"`** suppresses detailed error messages to callers.
- **`autoentities` stays empty for now.** See section 10.

---

## 7. Publish the entities

### 7.1 A view

```json
"LoanSummary": {
  "description": "One row per active commercial loan, with borrower, relationship manager, balances, rate, status, and days to maturity. Use for questions about individual loans, maturities, and loan-level balances.",
  "source": {
    "object": "mcp.vw_loan_summary",
    "type": "view"
  },
  "fields": [
    { "name": "LoanId",              "description": "Stable numeric loan identifier", "primary-key": true },
    { "name": "LoanNumber",          "description": "Business loan reference, format CL-YYYY-NNNN, for example CL-2024-0187" },
    { "name": "BorrowerName",        "description": "Borrower legal entity name" },
    { "name": "Industry",            "description": "Borrower industry. Valid values: Manufacturing, Healthcare, Retail, Technology, Construction, Transportation" },
    { "name": "RelationshipManager", "description": "Full name of the relationship manager who owns the borrower" },
    { "name": "Region",              "description": "Relationship manager region. Valid values: Midwest, Northeast, Southeast, West" },
    { "name": "OriginationDate",     "description": "Date the loan was originated (UTC, ISO 8601)" },
    { "name": "MaturityDate",        "description": "Contractual maturity date (UTC, ISO 8601)" },
    { "name": "CommittedAmount",     "description": "Total committed facility amount in USD" },
    { "name": "OutstandingBalance",  "description": "Current outstanding principal balance in USD" },
    { "name": "InterestRate",        "description": "Current annual interest rate as a decimal, for example 0.0725 for 7.25 percent" },
    { "name": "LoanStatus",          "description": "Loan status. Valid values: ACTIVE, PAID_OFF, DEFAULTED, RESTRUCTURED" },
    { "name": "DaysToMaturity",      "description": "Whole days from today until maturity. Negative if already matured" }
  ],
  "permissions": [
    { "role": "Mcp.Invoke",    "actions": [ { "action": "read" } ] },
    { "role": "authenticated", "actions": [ { "action": "read" } ] }
  ],
  "mcp": { "dml-tools": true, "custom-tool": false }
}
```

Six things are load-bearing here:

1. **Entity name is what the agent says.** `LoanSummary` reads better than `vw_loan_summary`.
2. **`description` says what it contains *and when to use it*.** The second half drives tool selection.
3. **`type` must be `"view"`.** Getting this wrong fails at startup.
4. **Exactly one field carries `"primary-key": true`.** DAB needs it for pagination; startup fails without it.
5. **Field descriptions carry units, formats and valid values.** More on this below.
6. **Only `read`.** No create, update or delete anywhere.

#### Field descriptions are where the quality is

Microsoft's guidance on constrained values is the highest-value line in the whole documentation set:

> *"When a column stores a fixed set of valid values, list them in the description. Without explicit valid values, agents may hallucinate similar but incorrect strings (for example, `Production` instead of the valid value `Prod`)."*

Applied to the example: without `"Valid values: ACTIVE, PAID_OFF, DEFAULTED, RESTRUCTURED"`, an agent asked for defaulted loans will filter on `'Defaulted'` or `'DEFAULT'`, get zero rows, and report — confidently — that you have no defaulted loans. **A wrong answer that looks right is worse than an error.**

Four things to include whenever they apply:

| Include | Example |
| --- | --- |
| **Units** | "in USD", "in whole days", "as a decimal, 0.0725 for 7.25 percent" |
| **Format** | "format CL-YYYY-NNNN", "UTC, ISO 8601" |
| **Valid values** | "Valid values: ACTIVE, PAID_OFF, DEFAULTED, RESTRUCTURED" |
| **Business meaning** | "Negative if already matured" |

### 7.2 A stored procedure as a named tool

```json
"GetLoanByNumber": {
  "description": "Returns the full detail for exactly one loan, given its business loan number such as CL-2024-0187. Use this when the user names a specific loan rather than describing a set of loans.",
  "source": {
    "object": "mcp.usp_GetLoanByNumber",
    "type": "stored-procedure",
    "parameters": [
      { "name": "LoanNumber", "description": "Business loan reference in the format CL-YYYY-NNNN", "required": true }
    ]
  },
  "permissions": [
    { "role": "Mcp.Invoke",    "actions": [ { "action": "execute" } ] },
    { "role": "authenticated", "actions": [ { "action": "execute" } ] }
  ],
  "mcp": { "custom-tool": true, "dml-tools": false }
}
```

Differences from a view, all of them deliberate:

- `type` is `"stored-procedure"`, and `parameters` are declared with descriptions.
- The action is `execute`, not `read`.
- **`"custom-tool": true`** publishes it as its own named tool.
- **`"dml-tools": false`** stops it also appearing through the generic tools.

**The name the agent uses is snake_case.** Entity `GetLoanByNumber` becomes tool `get_loan_by_number`. Use that form in the agent's allowlist — the PascalCase name is not accepted.

One caveat from the documentation: the tool's `inputSchema` currently returns empty properties, so the agent infers parameters from your description. Another reason to name the format explicitly.

`custom-tool` is only valid on stored-procedure entities. Setting it on a view is a startup error.

### 7.3 What the finished set looks like

| Entity | Source | Type | Agent sees |
| --- | --- | --- | --- |
| `LoanSummary` | `mcp.vw_loan_summary` | view | read, aggregate |
| `BorrowerExposure` | `mcp.vw_borrower_exposure` | view | read, aggregate |
| `DelinquencyWatchlist` | `mcp.vw_delinquency_watchlist` | view | read, aggregate |
| `GetLoanByNumber` | `mcp.usp_GetLoanByNumber` | stored procedure | `get_loan_by_number` |

Three views, one procedure, six questions answered. That is the right size to start.

### 7.4 The two roles

You will notice every entity lists both `Mcp.Invoke` and `authenticated`, with identical permissions. This is intentional. Role selection differs depending on how the request arrives and whether the client sends an `X-MS-API-ROLE` header. Listing both avoids a class of confusing authorisation failures.

Neither role grants create, update, delete, raw-table access or arbitrary SQL. And the database-level `mcp_reader` role remains the real boundary regardless.

**Never set an entity to `anonymous` to fix a role problem.** That removes authentication from the entity entirely.

---

## 8. If a view must span databases

Section 3.4 recommends keeping views inside one database. When you genuinely cannot, the identity setup changes — and this is exactly the failure you hit last week.

`CREATE USER ... FROM EXTERNAL PROVIDER` creates a **contained database user**. It exists only inside that one database and has no server-level principal behind it. When a view reaches into a second database, SQL has nothing to map the caller to:

```text
The server principal "<client-id>@<tenant-id>" is not able to access
the database "<other-database>" under the current security context
```

Creating a second contained user in the other database does not help — they are two unrelated principals, not one identity seen from both.

SQL Managed Instance supports **server-level Entra logins**, which Azure SQL Database does not. That gives you one principal every database can recognise:

```sql
-- Once, at the instance level
USE master;
GO
CREATE LOGIN [<mcp-uami-name>] FROM EXTERNAL PROVIDER;
GO

-- Then in EVERY database the view touches
USE [<database>];
GO
DROP USER IF EXISTS [<mcp-uami-name>];          -- remove the contained user first
CREATE USER [<mcp-uami-name>] FROM LOGIN [<mcp-uami-name>];

IF DATABASE_PRINCIPAL_ID(N'mcp_reader') IS NULL
    CREATE ROLE [mcp_reader] AUTHORIZATION [dbo];

ALTER ROLE [mcp_reader] ADD MEMBER [<mcp-uami-name>];
GO
```

Three things to know:

- **`DROP USER` first.** An existing contained user with the same name blocks the login-backed one.
- **The role and its grants are per-database.** `mcp_reader`, its membership, and every `GRANT` must exist in each database involved.
- **`CREATE LOGIN ... FROM EXTERNAL PROVIDER` requires Directory Readers** on the SQL MI server identity. You already have this — it is why the contained user worked.

The trade-off is honest: a server-level login is a broader principal than a contained user. The mitigation is that it grants nothing by itself. Every actual permission still comes from named-object grants via `mcp_reader` in each database.

---

## 9. Validate, then test

### 9.1 Validate the configuration

```powershell
# Placeholder connection string — this checks shape, not connectivity
$env:DATABASE_CONNECTION_STRING = 'Server=tcp:placeholder,1433;Initial Catalog=LendingOps;Authentication=Active Directory Managed Identity;User Id=00000000-0000-0000-0000-000000000000;Encrypt=True;TrustServerCertificate=False;'

dab validate --config ./dab-config.json
```

Expect `The config satisfies the schema requirements`. This checks shape only — object names and permissions are validated at startup against the live database.

### 9.2 Read the startup logs

The container's first thirty seconds are the most informative moment in the whole process. It resolves every entity against the database, and failures are specific:

| Log message | Cause | Fix |
| --- | --- | --- |
| `Cannot obtain schema for entity ...` | Object missing, or identity cannot see it | Check the object exists; check the grant; if cross-database, see section 8 |
| `... is not able to access the database ...` | Contained user, cross-database view | Section 8 |
| Missing primary key | No field marked `primary-key` | Mark exactly one |
| `custom-tool` invalid | Set on a view or table | Only valid on stored procedures |
| Login failed | Connection string, or identity not in `mcp_reader` | Verify both |

### 9.3 Test in three layers

Diagnose in this order. Each layer removes a whole class of cause.

**Layer 1 — SQL.** Connect as the MCP identity and select from each view directly. If this fails, nothing above it can work.

**Layer 2 — MCP.** With the container running, confirm `describe_entities` returns your entities *with their field descriptions*. If fields come back empty, the agent is guessing and you have found the problem before your users did.

**Layer 3 — agent.** Run your ten to fifteen stakeholder questions. Record every answer.

### 9.4 Prove the denials

Positive tests show it works. **Negative tests are what a security reviewer will ask for.** Both must pass:

- Ask the agent for something from a base table — `dbo.Borrower`, or anything containing `TaxId`. It must not be able to reach it.
- Ask the agent to change something — update a balance, delete a loan. It must refuse.

Capture the output. That evidence is part of the handoff.

### 9.5 When an answer is wrong

Most early wrong answers are **description problems, not configuration problems.** Work through this order:

1. Did it pick the wrong entity? → the entity `description` is not distinguishing enough.
2. Did it filter on a value that returned nothing? → valid values are missing from the field description.
3. Did it misread a number? → units are missing.
4. Did it invent a column? → that field has no description, or is not published.

Fix the description, restart, re-run. This loop is normal, and it is where the quality comes from.

---

## 10. Scaling beyond the first few views

Once the pattern holds, hand-writing every entity does not scale. Data API builder supports `autoentities`, which publishes objects by SQL `LIKE` pattern:

```json
"autoentities": {
  "curated": {
    "patterns": { "include": [ "mcp.%" ], "name": "{object}" },
    "template": {
      "mcp":     { "dml-tools": true },
      "rest":    { "enabled": false },
      "graphql": { "enabled": false }
    },
    "permissions": [
      { "role": "Mcp.Invoke",    "actions": [ { "action": "read" } ] },
      { "role": "authenticated", "actions": [ { "action": "read" } ] }
    ]
  }
}
```

This is where the dedicated `mcp` schema pays off: `include: ["mcp.%"]` publishes exactly what your data owners put in that schema, and nothing else.

**Explicit entities take precedence over a pattern match of the same name.** So the two combine well — hand-curate your most important views with full field descriptions, let the pattern cover the long tail.

Two cautions:

- **Pattern-published entities have no field descriptions.** Everything in section 7 about answer quality applies in reverse. Use the pattern for breadth, keep hand-written entities for the views that matter.
- **Confirm views are matched, not just tables.** The configuration reference describes autoentities as matching "database objects"; the underlying JSON schema wording says "tables". We have not yet confirmed which is authoritative. Check with `dab auto-config-simulate` before relying on it.

`dab auto-config-simulate` previews exactly which objects a pattern would match, without changing anything. It is the right artefact to show your data owners.

---

## 11. Checklist

Work top to bottom. Do not skip ahead — each step assumes the one above.

**Decide**

- [ ] Collected 10-15 real questions from business stakeholders
- [ ] Chosen 3–5 views that answer them
- [ ] Confirmed no view exposes sensitive columns
- [ ] Confirmed each view sits in one database, or accepted section 8

**Build in SQL**

- [ ] `mcp` schema created
- [ ] Views created and returning rows
- [ ] Stored procedures created, if any
- [ ] `mcp_reader` role created
- [ ] `GRANT SELECT` / `GRANT EXECUTE` on named objects only — no `db_datareader`
- [ ] MCP identity added to `mcp_reader`
- [ ] Grants verified by query (section 4.7)

**Configure**

- [ ] Runtime: MCP on, REST and GraphQL off
- [ ] Write tools disabled; `execute_entity` disabled
- [ ] One entity per view, `type: "view"`
- [ ] Exactly one `primary-key` per entity
- [ ] Every field has a description with units, format and valid values
- [ ] Stored procedures: `custom-tool: true`, `dml-tools: false`, parameters described
- [ ] Both `Mcp.Invoke` and `authenticated` roles present, read/execute only

**Validate**

- [ ] `dab validate` passes
- [ ] Audience and tenant placeholders substituted in the built image
- [ ] Container starts clean; no schema errors in the logs
- [ ] `describe_entities` returns entities **with** field descriptions

**Test**

- [ ] All stakeholder questions run and recorded
- [ ] Base-table access proven denied
- [ ] Write operations proven denied
- [ ] Agent tool allowlist limited to intended tools, snake_case names correct

---

## 12. Reference

| Topic | Source |
| --- | --- |
| DML tool reference | learn.microsoft.com/azure/data-api-builder/mcp/data-manipulation-language-tools |
| Adding descriptions | learn.microsoft.com/azure/data-api-builder/mcp/how-to-add-descriptions |
| Custom tools for procedures | learn.microsoft.com/azure/data-api-builder/mcp/how-to-configure-custom-tools |
| Configuration reference | learn.microsoft.com/azure/data-api-builder/configuration |
| Role-based access control | learn.microsoft.com/azure/data-api-builder/authorization |
| Entra logins for SQL MI | learn.microsoft.com/azure/azure-sql/managed-instance/aad-security-configure-tutorial |
| Reference implementation | github.com/jamesiford/foundry-sql-mcp, branch `demo/public-evaluation` |
| Working config to copy | `src/mcp-server/dab-config.json` in that repository |

---



