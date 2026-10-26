#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$script_dir/lib.sh"
repo_root="$(akari_repo_root)"

akari_resolve_sdk_binaries "$repo_root"
flutter_bin="$AKARI_RESOLVED_FLUTTER_BIN"
dart_bin="$AKARI_RESOLVED_DART_BIN"

if [[ -z "$flutter_bin" || ! -x "$flutter_bin" || -z "$dart_bin" || ! -x "$dart_bin" ]]; then
  printf '%s\n' 'Run fvm install, or set AKARI_FLUTTER_BIN and AKARI_DART_BIN to SDK executables.' >&2
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
