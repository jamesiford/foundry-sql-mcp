# Synthetic Data

This directory is reserved for the future synthetic wealth-management dataset, schema migrations, seed generator, approved views, stored procedures, and SQL role scripts.

Phase 2 has deployed an Entra-only SQL Managed Instance but contains no database schema, data, connection strings, or seeding logic. Phase 3 must keep all records synthetic, make generation repeatable, and expose agent-facing data only through the approved views and stored procedures documented in this repository.

Phase 4 must create named-object SQL grants through `agent_reader` and `mcp_reader`; it must not use `db_datareader`, `db_datawriter`, or `db_owner`. Foundry IQ projections need a discoverable single-column key, high-water-mark support, and soft-delete handling where required.
