#!/usr/bin/env python3
"""Extract BLE restore file contents from agent transcript."""
import json
import os
import re
from pathlib import Path

TRANSCRIPT = Path(
    r"C:\Users\Admin2\.cursor\projects\c-Users-Admin2-Desktop-HW2-0\agent-transcripts"
    r"\46501954-3e67-4c2a-b321-f2654ad487bd\46501954-3e67-4c2a-b321-f2654ad487bd.jsonl"
)
OUT_DIR = Path(r"c:\Users\Admin2\Desktop\HW2.0\_ble_restore_extract")


def walk(obj, found):
    if isinstance(obj, dict):
        name = obj.get("name") or obj.get("toolName") or obj.get("tool")
        # Cursor tool_use format
        if name in ("Write", "StrReplace") or (
            isinstance(name, str) and name.endswith("Write")
        ):
            args = obj.get("input") or obj.get("arguments") or obj.get("params") or {}
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except Exception:
                    args = {}
            found.append({"name": name, "args": args, "raw_keys": list(obj.keys())})
        for v in obj.values():
            walk(v, found)
    elif isinstance(obj, list):
        for item in obj:
            walk(item, found)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    lines = TRANSCRIPT.read_text(encoding="utf-8").splitlines()
    print(f"Total lines: {len(lines)}")

    # Focus on 1240-1270, but also scan all for target paths
    targets = [
        "ble_block_client.dart",
        "connect_block_ble_screen.dart",
        "telemetry_session.dart",
        "alert_notification_service.dart",
        "BUILD-ANDROID-BLE.md",
        "AndroidManifest.xml",
        "pubspec.yaml",
        "router.dart",
        "settings_screen.dart",
        "build.gradle.kts",
    ]

    index = []
    for i, line in enumerate(lines, start=1):
        if i < 1200:
            # still check for target filenames in later extraction pass
            if not any(t in line for t in targets):
                continue
        elif i > 1300 and not any(t in line for t in targets):
            continue

        try:
            obj = json.loads(line)
        except Exception as e:
            if 1240 <= i <= 1270:
                print(f"LINE {i}: parse error {e}")
            continue

        found = []
        walk(obj, found)
        for item in found:
            args = item["args"] or {}
            path = args.get("path") or ""
            if not any(t in path for t in targets):
                continue
            entry = {
                "line": i,
                "tool": item["name"],
                "path": path,
                "has_contents": "contents" in args,
                "has_old": "old_string" in args,
                "has_new": "new_string" in args,
                "contents_len": len(args.get("contents") or ""),
                "new_len": len(args.get("new_string") or ""),
            }
            index.append(entry)
            # dump args to file
            safe = Path(path).name.replace(".", "_")
            dump = OUT_DIR / f"L{i:04d}_{item['name']}_{safe}.json"
            dump.write_text(json.dumps(args, ensure_ascii=False, indent=2), encoding="utf-8")
            print(
                f"L{i}: {item['name']} {path} "
                f"contents={entry['contents_len']} new={entry['new_len']}"
            )

    (OUT_DIR / "index.json").write_text(
        json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"Wrote {len(index)} tool dumps to {OUT_DIR}")

    # Also print preview of lines 1249-1266 structure
    for i in range(1249, min(1267, len(lines) + 1)):
        line = lines[i - 1]
        print(f"\n=== LINE {i} len={len(line)} ===")
        try:
            obj = json.loads(line)
            print("keys:", list(obj.keys()))
            found = []
            walk(obj, found)
            for item in found:
                path = (item["args"] or {}).get("path", "?")
                print(f"  tool={item['name']} path={path}")
        except Exception as e:
            print("parse fail:", e)
            print(line[:400])


if __name__ == "__main__":
    main()
