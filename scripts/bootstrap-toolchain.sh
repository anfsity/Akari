#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$script_dir/lib.sh"
repo_root="$(akari_repo_root)"

akari_require_command cargo
akari_require_file "$repo_root/crates/akari-backend/Cargo.toml" 'backend Cargo manifest'

cd -- "$repo_root"

akari_resolve_sdk_binaries "$repo_root"
if [[ -z "${AKARI_RESOLVED_FLUTTER_BIN:-}" || ! -x "$AKARI_RESOLVED_FLUTTER_BIN" ]]; then
  akari_require_command fvm
  fvm install
  fvm use --skip-pub-get
  akari_resolve_sdk_binaries "$repo_root"
fi

flutter_bin="${AKARI_RESOLVED_FLUTTER_BIN:-}"
dart_bin="${AKARI_RESOLVED_DART_BIN:-}"
flutter_cmd=(fvm flutter)
dart_cmd=(fvm dart)
if [[ -n "$flutter_bin" && -x "$flutter_bin" ]]; then
  flutter_cmd=("$flutter_bin")
fi
if [[ -n "$dart_bin" && -x "$dart_bin" ]]; then
  dart_cmd=("$dart_bin")
fi

"${flutter_cmd[@]}" config --enable-linux-desktop
"${flutter_cmd[@]}" pub get
"${dart_cmd[@]}" run packages/akari_cli/bin/akari.dart generate-scenes
cargo fetch --manifest-path "$repo_root/crates/Cargo.toml" --locked
printf '%s\n' 'Flutter toolchain ready.'
"${flutter_cmd[@]}" doctor -v
