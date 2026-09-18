#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

cd -- "$repo_root"
"$repo_root/scripts/generate-scenes.sh"
rm -f build/perf/scene_report.json
fvm flutter drive \
  --profile \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/performance/scene_performance_test.dart
fvm dart run tool/perf/compare_perf.dart \
  --baseline tool/perf/baselines/default.json \
  --candidate build/perf/scene_report.json
