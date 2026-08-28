#!/usr/bin/env python3
"""List ALL Write/StrReplace in BLE session subagents."""
import json
from pathlib import Path

ROOT = Path(
    r"C:\Users\Admin2\.cursor\projects\c-Users-Admin2-Desktop-HW2-0\agent-transcripts"
    r"\46501954-3e67-4c2a-b321-f2654ad487bd"
)


def walk_tools(obj, found):
    if isinstance(obj, dict):
        name = obj.get("name") or obj.get("toolName")
        if name in ("Write", "StrReplace", "search_replace", "write"):
            args = obj.get("input") or obj.get("arguments") or obj.get("params") or {}
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except Exception:
                    args = {"_raw": args[:200]}
            found.append({"name": name, "path": (args or {}).get("path"), "keys": list((args or {}).keys())})
        # Also check type field for tool_use
        if obj.get("type") in ("tool_use", "function_call"):
            n = obj.get("name")
            args = obj.get("input") or obj.get("arguments") or {}
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except Exception:
                    args = {}
            found.append({"name": n, "type": obj.get("type"), "path": (args or {}).get("path"), "keys": list((args or {}).keys())[:20]})
        for v in obj.values():
            walk_tools(v, found)
    elif isinstance(obj, list):
        for item in obj:
            walk_tools(item, found)


def main():
    for path in sorted(ROOT.rglob("*.jsonl")):
        lines = path.read_text(encoding="utf-8").splitlines()
        print(f"\n=== {path.relative_to(ROOT)} ({len(lines)} lines) ===")
        any_tools = False
        for i, line in enumerate(lines, 1):
            try:
                obj = json.loads(line)
            except Exception:
                continue
            found = []
            walk_tools(obj, found)
            # filter interesting
            for t in found:
                p = t.get("path") or ""
                n = t.get("name") or ""
                if n in ("Write", "StrReplace", "write", "search_replace") or "ble" in p.lower() or "Ble" in p:
                    print(f"  L{i}: {n} path={p}")
                    any_tools = True
                elif n and n not in ("Read", "Shell", "Grep", "Glob", "TodoWrite", "ReadLints", "Delete", "EditNotebook", "WebSearch", "WebFetch", "Task", "AwaitShell", "UpdateCurrentStep", "SwitchMode", "GetMcpTools", "CallMcpTool", "FetchMcpResource", "GenerateImage"):
                    # unknown tools
                    if any(x in str(t).lower() for x in ("ble", "pubspec", "manifest", "notification", "telemetry", "router", "settings")):
                        print(f"  L{i}: OTHER {n} path={p} keys={t.get('keys')}")
                        any_tools = True
        if not any_tools:
            # print roles briefly
            roles = []
            for line in lines[:5]:
                try:
                    roles.append(json.loads(line).get("role") or json.loads(line).get("type"))
                except Exception:
                    roles.append("?")
            print(f"  (no write tools) first roles={roles}")


if __name__ == "__main__":
    main()
