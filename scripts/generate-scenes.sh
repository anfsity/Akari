#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

if [[ -n "${MOZAIS_DART_BIN:-}" ]]; then
  dart_command=("$MOZAIS_DART_BIN")
else
  dart_command=(fvm dart)
fi
for theme_dir in mozais_theme_default mozais_theme_fallback; do
  cd -- "$repo_root/packages/$theme_dir"
  "${dart_command[@]}" run build_runner build
done
