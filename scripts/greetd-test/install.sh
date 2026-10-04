#!/usr/bin/env bash
set -euo pipefail
source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$source_dir/../.." && pwd)"
test_root=/opt/mozais-test
if [[ "$EUID" -ne 0 ]]; then
  echo 'Run this installer with sudo to build and install the test artifacts.' >&2
  exit 1
fi
for unit in mozais-test.service mozais-restore.timer; do
  if systemctl is-active --quiet "$unit"; then
    echo "$unit is active. Restore before installing." >&2
    exit 1
  fi
done
build_user="${SUDO_USER:-$(stat -c '%U' "$repo_root")}"
printf 'Building the current default theme and production backend as %s...\n' "$build_user"
# Build as the caller so SDK and repository caches retain their user ownership.
# Direct root invocation uses the repository owner for the same reason.
runuser -u "$build_user" -- bash -c '
  set -euo pipefail
  cd -- "$1"
  source scripts/lib.sh
  export PATH="$HOME/.cargo/bin:$PATH"
  mozais_run_dev_cli "$1" build --theme "$1/themes/default" --mode release --platform linux --jobs 4
' bash "$repo_root"

backend="$repo_root/build/out/backend"
bundle="$repo_root/build/out/default"
test -x "$backend"
test -x "$bundle/greeter"
if layout="$(runuser -u "$build_user" -- python3 "$source_dir/display-layout.py" capture)"; then
  echo 'Captured the current desktop display order.'
else
  layout=""
  echo 'No display order captured; keeping the installed layout, if present.'
fi
backup="$test_root/backups/$(date +%Y%m%d-%H%M%S)-$$"
install -d -m 0755 "$backup"
for path in frontend backend scripts start.sh restore.sh launch.sh greetd.toml sway.conf display-layout.json display-layout.py mock-power; do
  if [[ -e "$test_root/$path" ]]; then
    cp -a "$test_root/$path" "$backup/"
  fi
done
cp -aL "$bundle/." "$test_root/frontend/"
install -m 0755 "$backend" "$test_root/backend"
install -m 0755 "$source_dir/start.sh" "$source_dir/restore.sh" "$source_dir/launch.sh" "$test_root/"
install -m 0644 "$source_dir/greetd.toml" "$source_dir/sway.conf" "$test_root/"
install -m 0644 "$source_dir/display-layout.py" "$test_root/"
if [[ -n "$layout" ]]; then
  printf '%s\n' "$layout" > "$test_root/display-layout.json"
  chmod 0644 "$test_root/display-layout.json"
fi
install -m 0755 "$repo_root/scripts/debug-dbus.sh" "$repo_root/scripts/lib.sh" "$test_root/scripts/"
rm -f "$test_root/mock-power"
echo "Installed test files; previous version: $backup"
echo 'No display manager was started or stopped.'
