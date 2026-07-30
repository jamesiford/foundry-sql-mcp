from __future__ import annotations

import json
import os
from pathlib import Path

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import MCPTool, PromptAgentDefinition
from azure.identity import DefaultAzureCredential


AGENT_NAME = "transfer-agent-sql-mcp-demo"
ALLOWED_TOOLS = [
    "describe_entities",
    "read_records",
    "aggregate_records",
    "get_transfer_summary_by_client",
    "get_open_risk_alerts",
    "get_advisor_pipeline",
]


def required_environment(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"Required environment variable {name} is not set.")
    return value


def main() -> None:
    project_endpoint = required_environment("AZURE_AI_PROJECT_ENDPOINT")
    model_deployment = required_environment("AZURE_AI_MODEL_DEPLOYMENT_NAME")
    mcp_endpoint = required_environment("MCP_ENDPOINT")
    connection_name = required_environment("MCP_PROJECT_CONNECTION_NAME")
    instructions = Path(__file__).with_name("instructions.txt").read_text(encoding="utf-8")

    project_client = AIProjectClient(
        endpoint=project_endpoint,
        credential=DefaultAzureCredential(),
    )
    tool = MCPTool(
        server_label="sql-mcp-demo",
        server_url=mcp_endpoint,
        allowed_tools=ALLOWED_TOOLS,
        require_approval="never",
        project_connection_id=connection_name,
    )
    agent = project_client.agents.create_version(
        agent_name=AGENT_NAME,
        definition=PromptAgentDefinition(
            model=model_deployment,
            instructions=instructions,
            tools=[tool],
        ),
    )
    print(
        json.dumps(
            {
                "id": agent.id,
                "name": agent.name,
                "version": agent.version,
                "project_endpoint": project_endpoint,
                "mcp_endpoint": mcp_endpoint,
                "allowed_tools": ALLOWED_TOOLS,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()