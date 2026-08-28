#!/usr/bin/env python3
"""Deep dump of transcript lines that mention BLE files, including tool formats."""
import json
from pathlib import Path

FILES = [
    Path(r"C:\Users\Admin2\.cursor\projects\c-Users-Admin2-Desktop-HW2-0\agent-transcripts\46501954-3e67-4c2a-b321-f2654ad487bd\46501954-3e67-4c2a-b321-f2654ad487bd.jsonl"),
    Path(r"C:\Users\Admin2\.cursor\projects\c-Users-Admin2-Desktop-HW2-0\agent-transcripts\46501954-3e67-4c2a-b321-f2654ad487bd\subagents\968af33c-02c6-4d9f-aa57-43a605a83642.jsonl"),
    Path(r"C:\Users\Admin2\.cursor\projects\c-Users-Admin2-Desktop-HW2-0\agent-transcripts\46501954-3e67-4c2a-b321-f2654ad487bd\subagents\5fd8aa58-fec2-4375-b03c-2d457ae7a2fa.jsonl"),
]
OUT = Path(r"c:\Users\Admin2\Desktop\HW2.0\_ble_restore_extract")
OUT.mkdir(exist_ok=True)


def summarize(obj, depth=0, max_depth=6):
    if depth > max_depth:
        return "..."
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            if k in ("contents", "old_string", "new_string", "text", "content") and isinstance(v, str) and len(v) > 200:
                out[k] = f"<str len={len(v)} preview={v[:120]!r}...>"
            elif k == "arguments" and isinstance(v, str) and len(v) > 200:
                out[k] = f"<str len={len(v)}>"
                try:
                    parsed = json.loads(v)
                    out[k + "_parsed_keys"] = list(parsed.keys()) if isinstance(parsed, dict) else type(parsed).__name__
                    if isinstance(parsed, dict) and "path" in parsed:
                        out["path"] = parsed["path"]
                        if "contents" in parsed:
                            out["contents_len"] = len(parsed["contents"])
                except Exception:
                    pass
            else:
                out[k] = summarize(v, depth + 1, max_depth)
        return out
    if isinstance(obj, list):
        if len(obj) > 20:
            return [summarize(x, depth + 1, max_depth) for x in obj[:10]] + [f"... +{len(obj)-10} more"]
        return [summarize(x, depth + 1, max_depth) for x in obj]
    if isinstance(obj, str) and len(obj) > 300:
        return f"<str len={len(obj)} preview={obj[:150]!r}...>"
    return obj


def find_strings_with(obj, needle, hits, path=""):
    if isinstance(obj, dict):
        for k, v in obj.items():
            find_strings_with(v, needle, hits, f"{path}.{k}")
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            find_strings_with(v, needle, hits, f"{path}[{i}]")
    elif isinstance(obj, str) and needle in obj:
        hits.append((path, len(obj), obj[:200]))


def main():
    for path in FILES:
        print(f"\n######## {path.parent.name}/{path.name} ########")
        lines = path.read_text(encoding="utf-8").splitlines()
        for i, line in enumerate(lines, 1):
            if "ble_block_client" not in line and "BleBlockClient" not in line and "BUILD-ANDROID-BLE" not in line and "flutter_blue_plus" not in line:
                if "alert_notification_service" not in line or i < 1100:
                    continue
            print(f"\n--- L{i} len={len(line)} ---")
            try:
                obj = json.loads(line)
            except Exception as e:
                print("parse error", e)
                continue
            summary = summarize(obj)
            dump = OUT / f"structure_{path.stem}_L{i}.json"
            dump.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
            print("wrote", dump.name)
            # Also look for Write-like content containing class BleBlockClient
            for needle in ["class BleBlockClient", "startBle", "BUILD-ANDROID-BLE", "class AlertNotificationService"]:
                hits = []
                find_strings_with(obj, needle, hits)
                if hits:
                    print(f"  needle {needle}: {len(hits)} hits")
                    for pth, ln, prev in hits[:5]:
                        print(f"    {pth} len={ln}")


if __name__ == "__main__":
    main()
