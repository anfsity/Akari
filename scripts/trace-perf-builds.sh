#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

cd -- "$repo_root"
if [[ -n "${MOZAIS_FLUTTER_BIN:-}" ]]; then
  flutter_command=("$MOZAIS_FLUTTER_BIN")
  dart_command=("$(dirname -- "$MOZAIS_FLUTTER_BIN")/dart")
  MOZAIS_DART_BIN="${dart_command[0]}" \
    "$repo_root/scripts/generate-scenes.sh"
else
  flutter_command=(fvm flutter)
  dart_command=(fvm dart)
  "$repo_root/scripts/generate-scenes.sh"
fi
rm -f build/perf/scene_startup_wake_timeline.json
"${flutter_command[@]}" drive \
  -d linux \
  --profile \
  --no-dds \
  --dart-define=MOZAIS_PERF_TRACE_TIMELINE=true \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/performance/scene_performance_test.dart
printf 'Widget, layout, and paint timeline: %s\n' \
  "$repo_root/build/perf/scene_startup_wake_timeline.json"
"${dart_command[@]}" run tool/perf/summarize_timeline.dart \
  --input build/perf/scene_startup_wake_timeline.json
