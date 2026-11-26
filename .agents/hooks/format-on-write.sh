#!/usr/bin/env bash
set -euo pipefail

hook_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$hook_dir/../.." && pwd)"

target_path="$(
  python3 -c '
import json, sys
try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if payload.get("error"):
    sys.exit(0)
args = (payload.get("toolCall") or {}).get("args") or {}
path = args.get("Path") or args.get("path") or ""
if isinstance(path, str) and path:
    print(path)
'
)"

if [[ -n "$target_path" ]]; then
  case "$target_path" in
    "$repo_root"/*.dart|"$repo_root"/*.rs)
      "$repo_root/scripts/format-files.sh" "$target_path" >&2 || true
      ;;
  esac
fi

printf '{}\n'
