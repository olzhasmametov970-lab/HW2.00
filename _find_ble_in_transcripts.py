#!/usr/bin/env python3
"""Find ble_block_client and related Write ops in all transcripts."""
import json
from pathlib import Path

ROOT = Path(r"C:\Users\Admin2\.cursor\projects\c-Users-Admin2-Desktop-HW2-0\agent-transcripts")
KEYWORDS = [
    "ble_block_client",
    "connect_block_ble_screen",
    "alert_notification_service",
    "BUILD-ANDROID-BLE",
    "startBle",
    "BleBlockClient",
    "flutter_blue_plus",
]


def walk(obj, found):
    if isinstance(obj, dict):
        name = obj.get("name") or obj.get("toolName") or obj.get("tool")
        if name in ("Write", "StrReplace"):
            args = obj.get("input") or obj.get("arguments") or obj.get("params") or {}
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except Exception:
                    args = {}
            found.append({"name": name, "args": args})
        for v in obj.values():
            walk(v, found)
    elif isinstance(obj, list):
        for item in obj:
            walk(item, found)


def scan_file(path: Path):
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    hits = []
    for i, line in enumerate(lines, 1):
        if not any(k in line for k in KEYWORDS):
            continue
        # keyword hit
        tools = []
        try:
            obj = json.loads(line)
            found = []
            walk(obj, found)
            for item in found:
                p = (item["args"] or {}).get("path", "")
                if any(k in p or k in str(item["args"]) for k in KEYWORDS):
                    tools.append(
                        (
                            item["name"],
                            p,
                            len((item["args"] or {}).get("contents") or ""),
                            len((item["args"] or {}).get("new_string") or ""),
                        )
                    )
        except Exception:
            pass
        preview_kw = [k for k in KEYWORDS if k in line]
        hits.append((i, preview_kw, tools, len(line)))
    return len(lines), hits


def main():
    for path in sorted(ROOT.rglob("*.jsonl")):
        n, hits = scan_file(path)
        if not hits:
            continue
        print(f"\n===== {path.name} ({n} lines) =====")
        for i, kws, tools, llen in hits:
            print(f"  L{i} len={llen} kws={kws}")
            for t in tools:
                print(f"    tool={t}")


if __name__ == "__main__":
    main()
