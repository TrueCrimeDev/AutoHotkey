"""Write the actual engine's identity, CLI capabilities and MCP tool schemas.

Usage: python tools/describe_console.py ENGINE OUTPUT.json
The output is a build artifact, not a manually maintained feature list.
"""

import hashlib
import json
from pathlib import Path
import subprocess
import sys


def describe(engine):
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)

    def run(*args, input=None):
        result = subprocess.run([str(engine), *args], input=input, capture_output=True,
                                text=True, encoding="utf-8", timeout=15, creationflags=flags)
        if result.returncode:
            raise RuntimeError(f"Engine exited {result.returncode}: {result.stderr.strip()}")
        return result.stdout

    capabilities = json.loads(run("--capabilities"))
    requests = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "describe-console", "version": "1"}}},
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
    ]
    replies = [json.loads(line) for line in run("mcp", input="".join(json.dumps(r) + "\n" for r in requests)).splitlines()]
    by_id = {reply["id"]: reply for reply in replies if "id" in reply}
    for request_id in (1, 2):
        if request_id not in by_id or "result" not in by_id[request_id]:
            raise RuntimeError(f"Missing successful MCP response {request_id}: {by_id.get(request_id)}")
    tools = by_id[2]["result"]["tools"]
    if not tools or len({tool["name"] for tool in tools}) != len(tools):
        raise RuntimeError("MCP tool registry is empty or has duplicate names")
    return {
        "engine": engine.name,
        "sha256": hashlib.sha256(engine.read_bytes()).hexdigest(),
        "version": run("--version").strip(),
        "capabilities": capabilities,
        "mcp": {"serverInfo": by_id[1]["result"]["serverInfo"], "tools": tools},
    }


def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    engine, output = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    if not engine.is_file():
        print(f"Engine does not exist: {engine}", file=sys.stderr)
        return 2
    artifact = describe(engine)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(artifact, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    print(f"Wrote {output.name}: {len(artifact['mcp']['tools'])} MCP tools, SHA-256 {artifact['sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
