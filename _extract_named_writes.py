#!/usr/bin/env python3
"""Extract specific file Writes from transcript by basename."""
import json
from pathlib import Path

path = Path(
    r"C:\Users\Admin2\.cursor\projects\c-Users-Admin2-Desktop-HW2-0\agent-transcripts"
    r"\46501954-3e67-4c2a-b321-f2654ad487bd\46501954-3e67-4c2a-b321-f2654ad487bd.jsonl"
)
out = Path(r"c:\Users\Admin2\Desktop\HW2.0\_ble_restore_extract")
out.mkdir(exist_ok=True)

basenames = {
    "alert_notification_service.dart",
    "telemetry_session.dart",
    "connect_block_ble_screen.dart",
    "ble_block_client.dart",
    "ble_uuids.dart",
    "AndroidManifest.xml",
    "BUILD-ANDROID-BLE.md",
    "pubspec.yaml",
    "router.dart",
    "settings_screen.dart",
    "ble_config.h",
    "BLE.md",
}

last_writes = {}
all_hits = []

with path.open("r", encoding="utf-8", errors="replace") as f:
    for i, line in enumerate(f, 1):
        try:
            obj = json.loads(line)
        except Exception:
            continue
        content = (obj.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        for part in content:
            if not isinstance(part, dict) or part.get("type") != "tool_use":
                continue
            name = part.get("name")
            inp = part.get("input")
            if not isinstance(inp, dict):
                continue
            p = inp.get("path") or ""
            base = Path(p).name if p else ""
            if base not in basenames:
                continue
            all_hits.append((i, name, p, len(inp.get("contents") or ""), len(inp.get("new_string") or "")))
            if name == "Write" and "contents" in inp:
                last_writes[base] = (i, inp["contents"], p)

print("ALL HITS:")
for h in all_hits:
    print(f"  L{h[0]} {h[1]} {h[2]} c={h[3]} n={h[4]}")

print("\nLAST WRITES:")
for k, (i, c, p) in sorted(last_writes.items()):
    dest = out / f"from_transcript_{k}"
    dest.write_text(c, encoding="utf-8")
    print(f"  {k}: L{i} len={len(c)} -> {dest.name}")

# Also search raw for WIFI / HydroWin- / startBle in any Write contents
print("\nScanning Write contents for BLE keywords...")
with path.open("r", encoding="utf-8", errors="replace") as f:
    for i, line in enumerate(f, 1):
        if '"name":"Write"' not in line:
            continue
        if not any(k in line for k in ("flutter_blue", "BleBlock", "startBle", "updateLiveSummary", "HydroWin-", "WIFI_API", "BUILD-ANDROID-BLE", "FlutterBluePlus")):
            continue
        try:
            obj = json.loads(line)
        except Exception:
            print(f"L{i}: Write with BLE kw but parse fail, len={len(line)}")
            continue
        for part in (obj.get("message") or {}).get("content") or []:
            if not isinstance(part, dict) or part.get("name") != "Write":
                continue
            inp = part.get("input") or {}
            p = inp.get("path") or ""
            c = inp.get("contents") or ""
            print(f"L{i}: Write {p} len={len(c)}")
            if c:
                (out / f"ble_kw_L{i}_{Path(p).name}").write_text(c, encoding="utf-8")
