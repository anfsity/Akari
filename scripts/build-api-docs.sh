#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_bin="${MOZAIS_FLUTTER_BIN:-$repo_root/.fvm/flutter_sdk/bin/flutter}"
if [[ "$flutter_bin" != /* ]]; then
  flutter_bin="$repo_root/$flutter_bin"
fi
dart_bin="${MOZAIS_DART_BIN:-$(dirname -- "$flutter_bin")/dart}"
if [[ "$dart_bin" != /* ]]; then
  dart_bin="$repo_root/$dart_bin"
fi

if [[ ! -x "$flutter_bin" || ! -x "$dart_bin" ]]; then
  printf '%s\n' 'Run fvm install, or set MOZAIS_FLUTTER_BIN and MOZAIS_DART_BIN to SDK executables.' >&2
  exit 1
fi

output_root="$repo_root/docs/site/public/api/dart"
rm -rf -- "$output_root"
for package in theme_sdk scene scene_schema greeter_components; do
  cd -- "$repo_root/packages/$package"
  "$flutter_bin" pub get
  "$flutter_bin" analyze --no-pub lib
  "$dart_bin" doc --output "$output_root/$package" .
done
