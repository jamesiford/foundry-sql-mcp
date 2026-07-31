from __future__ import annotations

import json
import os
from pathlib import Path

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import MCPTool, PromptAgentDefinition
from azure.core.exceptions import ResourceNotFoundError
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


def definition_matches(current: dict, desired: dict) -> bool:
    current_tool = current.get("tools", [{}])[0]
    desired_tool = desired.get("tools", [{}])[0]
    current_allowed_tools = current_tool.get("allowed_tools", [])
    if isinstance(current_allowed_tools, dict):
        current_allowed_tools = current_allowed_tools.get("tool_names", [])
    desired_allowed_tools = desired_tool.get("allowed_tools", [])
    if isinstance(desired_allowed_tools, dict):
        desired_allowed_tools = desired_allowed_tools.get("tool_names", [])
    return (
        current.get("kind") == desired.get("kind")
        and current.get("model") == desired.get("model")
        and current.get("instructions") == desired.get("instructions")
        and current_tool.get("type") == desired_tool.get("type")
        and current_tool.get("server_label") == desired_tool.get("server_label")
        and current_tool.get("server_url") == desired_tool.get("server_url")
        and current_allowed_tools == desired_allowed_tools
        and current_tool.get("require_approval") == desired_tool.get("require_approval")
        and current_tool.get("project_connection_id")
        == desired_tool.get("project_connection_id")
    )


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
    definition = PromptAgentDefinition(
        model=model_deployment,
        instructions=instructions,
        tools=[tool],
    )
    desired_definition = definition.as_dict()
    try:
        current_versions = list(
            project_client.agents.list_versions(
                AGENT_NAME,
                limit=1,
                order="desc",
            )
        )
    except ResourceNotFoundError:
        current_versions = []
    reused = bool(
        current_versions
        and definition_matches(
            current_versions[0].as_dict().get("definition", {}),
            desired_definition,
        )
    )
    agent = (
        current_versions[0]
        if reused
        else project_client.agents.create_version(
            agent_name=AGENT_NAME,
            definition=definition,
        )
    )
    print(
        json.dumps(
            {
                "id": agent.id,
                "name": agent.name,
                "version": agent.version,
                "reused": reused,
                "project_endpoint": project_endpoint,
                "mcp_endpoint": mcp_endpoint,
                "allowed_tools": ALLOWED_TOOLS,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()