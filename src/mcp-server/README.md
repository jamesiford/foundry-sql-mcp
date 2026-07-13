# SQL MCP Server

This directory is reserved for Microsoft SQL MCP Server built on Data API builder.

Phase 2 has deployed the dedicated MCP managed identity and subnet, while the internal Container Apps environment requires a regional-capacity retry. No server code, container image, Data API builder configuration, or SQL connection configuration exists yet.

Phase 5 will pin Data API builder 2.x, validate Entra issuer/audience for inbound MCP calls, authenticate outbound SQL calls with the MCP UAMI, expose only approved views and stored procedures, disable writes, and include tests that prove raw tables and unapproved operations are unavailable. DAB permissions must narrow the surface further but cannot substitute for the `mcp_reader` SQL role.
