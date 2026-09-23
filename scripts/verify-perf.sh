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
for run_number in 1 2 3; do
  rm -f build/perf/scene_report.json
  "${flutter_command[@]}" drive \
    -d linux \
    --profile \
    --no-dds \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/performance/scene_performance_test.dart
  cp build/perf/scene_report.json "build/perf/scene_report_$run_number.json"
done
"${dart_command[@]}" run tool/perf/aggregate_perf.dart \
  --output build/perf/scene_report.json \
  --input build/perf/scene_report_1.json \
  --input build/perf/scene_report_2.json \
  --input build/perf/scene_report_3.json
"${dart_command[@]}" run tool/perf/compare_perf.dart \
  --baseline tool/perf/baselines/default.json \
  --candidate build/perf/scene_report.json
