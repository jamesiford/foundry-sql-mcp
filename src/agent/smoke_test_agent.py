from __future__ import annotations

import json
import os

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential


AGENT_NAME = "transfer-agent-sql-mcp-demo"
PROMPTS = [
    "Return the transfer summary for CLIENT-001.",
    "Show open High severity risk alerts.",
    "Summarize the transfer pipeline for advisor ADV-MIL-01.",
]


def main() -> None:
    project_endpoint = os.environ.get("AZURE_AI_PROJECT_ENDPOINT")
    if not project_endpoint:
        raise RuntimeError("AZURE_AI_PROJECT_ENDPOINT is not set.")

    project_client = AIProjectClient(
        endpoint=project_endpoint,
        credential=DefaultAzureCredential(),
    )
    openai_client = project_client.get_openai_client()
    results: list[dict[str, str]] = []
    for prompt in PROMPTS:
        response = openai_client.responses.create(
            input=prompt,
            extra_body={
                "agent_reference": {
                    "name": AGENT_NAME,
                    "type": "agent_reference",
                }
            },
        )
        results.append({"prompt": prompt, "response": response.output_text})

    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()