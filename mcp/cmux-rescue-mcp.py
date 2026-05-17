#!/usr/bin/env python3
"""cmux-rescue-mcp — zero-dependency MCP server for session restore.

stdlib only. Speaks MCP over stdio (newline-delimited JSON-RPC 2.0).
No `mcp` pip package, no framework — same zero-dep ethos as the CLI.

Wraps the `cmux-rescue` and `claude-session-restore` binaries so any
MCP client (Claude Code, Cursor, Codex, Claude Desktop) can:
  - list restorable Claude sessions (ranked, leverage-scored)
  - restore them into cmux workspaces (dry-run / top / picks / all / restart)
  - drive the generic terminal restorer (detect / new-plan / launch)

Register (Claude Code):
  claude mcp add cmux-rescue -- python3 /path/to/mcp/cmux-rescue-mcp.py

Env: CMUX_RESCUE_BIN (default: which cmux-rescue)
     CSR_BIN          (default: which claude-session-restore)
"""
from __future__ import annotations
import json, os, shutil, subprocess, sys

PROTOCOL = "2024-11-05"
RESCUE = os.environ.get("CMUX_RESCUE_BIN") or shutil.which("cmux-rescue") \
    or os.path.expanduser("~/.local/bin/cmux-rescue")
CSR = os.environ.get("CSR_BIN") or shutil.which("claude-session-restore") \
    or os.path.expanduser("~/.local/bin/claude-session-restore")

TOOLS = [
    {
        "name": "list_sessions",
        "description": "List restorable Claude sessions, newest first, with "
                       "cwd, first message and leverage score. Spawns nothing.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "limit": {"type": "integer", "default": 30,
                          "description": "max sessions to return"},
            },
        },
    },
    {
        "name": "cmux_rescue",
        "description": "Restore Claude sessions into fresh cmux workspaces. "
                       "Zero-dependency, idempotent (safe to re-run).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "top": {"type": "integer", "default": 10,
                        "description": "N newest sessions"},
                "picks": {"type": "integer", "default": 5,
                          "description": "M extra leverage-scored picks"},
                "all": {"type": "boolean", "default": False,
                        "description": "restore every closed session (cap 40)"},
                "dry_run": {"type": "boolean", "default": False,
                            "description": "print plan, spawn nothing"},
                "restart": {"type": "boolean", "default": False,
                            "description": "quit+relaunch cmux first "
                                           "(launchd-owned, survives quit)"},
            },
        },
    },
    {
        "name": "rescue",
        "description": "UNIVERSAL one-shot restore — auto-rank + spawn into "
                       "the CURRENT terminal (cmux, Ghostty, iTerm2, "
                       "Terminal.app, Kitty, WezTerm, Alacritty, tmux, Linux). "
                       "Zero config, no plan file.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "top": {"type": "integer", "default": 10,
                        "description": "N newest sessions"},
                "picks": {"type": "integer", "default": 5,
                          "description": "M extra leverage-scored picks"},
            },
        },
    },
    {
        "name": "claude_session_restore",
        "description": "Drive the universal cross-terminal restorer. "
                       "subcommand one of: detect, new-plan, launch, rescue.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "subcommand": {"type": "string",
                               "enum": ["detect", "new-plan", "launch",
                                        "rescue"]},
            },
            "required": ["subcommand"],
        },
    },
]


def _run(argv: list[str], timeout: int = 120) -> str:
    try:
        r = subprocess.run(argv, capture_output=True, text=True,
                            timeout=timeout)
        out = (r.stdout or "") + (("\n[stderr]\n" + r.stderr) if r.stderr else "")
        return out.strip() or f"(exit {r.returncode}, no output)"
    except FileNotFoundError:
        return f"ERROR: binary not found: {argv[0]}"
    except subprocess.TimeoutExpired:
        return f"ERROR: timed out after {timeout}s: {' '.join(argv)}"
    except Exception as e:  # noqa: BLE001
        return f"ERROR: {e}"


def call_tool(name: str, args: dict) -> str:
    if name == "list_sessions":
        # --dry-run --all is the no-spawn enumeration path
        out = _run([RESCUE, "--dry-run", "--all"])
        lines = [ln for ln in out.splitlines() if " would: " in ln]
        limit = int(args.get("limit", 30))
        return "\n".join(lines[:limit]) or out
    if name == "cmux_rescue":
        argv = [RESCUE]
        if args.get("all"):
            argv.append("--all")
        else:
            argv += ["--top", str(int(args.get("top", 10))),
                     "--picks", str(int(args.get("picks", 5)))]
        if args.get("dry_run"):
            argv.append("--dry-run")
        if args.get("restart"):
            argv.append("--restart")
        return _run(argv, timeout=300)
    if name == "rescue":
        return _run([CSR, "rescue",
                     str(int(args.get("top", 10))),
                     str(int(args.get("picks", 5)))], timeout=300)
    if name == "claude_session_restore":
        sub = str(args.get("subcommand", "")).strip()
        if sub not in ("detect", "new-plan", "launch", "rescue"):
            return "ERROR: subcommand must be detect|new-plan|launch|rescue"
        return _run([CSR, sub], timeout=300)
    return f"ERROR: unknown tool {name}"


def reply(msg_id, result=None, error=None):
    m = {"jsonrpc": "2.0", "id": msg_id}
    if error is not None:
        m["error"] = error
    else:
        m["result"] = result
    sys.stdout.write(json.dumps(m) + "\n")
    sys.stdout.flush()


def main() -> None:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            continue
        mid = req.get("id")
        method = req.get("method")
        params = req.get("params") or {}

        if method == "initialize":
            reply(mid, {
                "protocolVersion": PROTOCOL,
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "cmux-rescue", "version": "1.0.0"},
            })
        elif method == "notifications/initialized":
            continue  # notification, no reply
        elif method == "tools/list":
            reply(mid, {"tools": TOOLS})
        elif method == "tools/call":
            name = params.get("name", "")
            args = params.get("arguments") or {}
            text = call_tool(name, args)
            reply(mid, {"content": [{"type": "text", "text": text}]})
        elif method in ("ping",):
            reply(mid, {})
        elif mid is not None:
            reply(mid, error={"code": -32601,
                              "message": f"method not found: {method}"})


if __name__ == "__main__":
    main()
