# SQL MCP Server

SQL MCP Server is a feature of **Data API builder (DAB)**, not an application in this repository.

> **There is no server code to write.** Microsoft publishes the DAB container image. You supply a
> configuration file. That is the entire server.

## What is in this directory

| File | Purpose |
|---|---|
| `dab-config.json` | The data contract: connection, MCP tool policy, Entra JWT validation, and every entity exposed to the agent |
| `Dockerfile` | Two lines — pin the Microsoft DAB image, copy the config into it |
| `.dockerignore` | Keeps the build context minimal |

The complete `Dockerfile`:

```dockerfile
FROM mcr.microsoft.com/azure-databases/data-api-builder:2.0.9
COPY dab-config.json /App/dab-config.json
```

No compilation, no dependencies, no build toolchain. `scripts/build-demo-mcp.ps1` substitutes the
placeholder audience/tenant GUIDs into a copy of the config, hashes the result for a deterministic
image tag, and runs `az acr build`.

## How the configuration is structured

**`runtime.mcp.dml-tools`** — the global tool policy. This deployment enables `describe-entities`,
`read-records`, and `aggregate-records`, and disables every write tool plus the generic
`execute-entity`. A tool disabled here is invisible to agents regardless of entity permissions.

**`runtime.host.authentication`** — Entra JWT validation. The committed `audience` and `issuer` are
all-zero and all-one placeholders replaced at build time. The audience is the **bare application
client ID**, while the Foundry project connection uses `api://<client-id>`. These two forms are
intentionally different; mismatching them produces a `401` at agent-invocation time, far from the
cause.

**`entities`** — one entry per exposed view or stored procedure. Each carries a semantic
description, explicit field names and descriptions, one `primary-key` field, read-only permissions,
and an `mcp` block. Approved stored procedures are exposed as individually named custom tools
(`custom-tool: true`, `dml-tools: false`) rather than through the generic execute tool.

**`autoentities`** — deliberately empty. Wildcard discovery would expose newly created database
objects without review.

## Field descriptions are the interface, not documentation

Agents do not read your schema. They call `describe_entities`, which returns only what is written in
this file. An entity published without field descriptions leaves the agent guessing column names and
filter values — it will guess confidently and be wrong in ways that are hard to detect.

Where a column holds a fixed set of values, list them in the description. Without
`"Valid values: ACTIVE, PAID_OFF, DEFAULTED"`, an agent asked for defaulted records will filter on
`'Defaulted'`, return zero rows, and report that none exist.

## Security model

DAB permissions narrow the surface but **cannot grant access SQL itself denies**. The database-level
`mcp_reader` role, granted on named objects only, remains the authoritative boundary. Never use
`db_datareader`, `db_datawriter`, or `db_owner`.

Both `Mcp.Invoke` and the system `authenticated` role are listed on every entity with identical
read/execute-only permissions, because role selection differs by request surface. Never broaden an
entity to `anonymous` to resolve a role-selection problem.

## Adapting this to your own database

See [Configuring SQL MCP Server for your own databases](../../docs/configure-for-your-database.md)
for the full walkthrough: choosing which objects to expose, building curated views, granting least
privilege, and writing entity and field descriptions that produce accurate answers.
