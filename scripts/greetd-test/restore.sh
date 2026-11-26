#!/usr/bin/env bash
set -euo pipefail
test_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$EUID" -ne 0 ]]; then
  printf 'Run with sudo: sudo %s/restore.sh\n' "$test_root" >&2
  exit 1
fi
# Parent start.sh already holds /run/akari/test.lock during synchronous EXIT cleanup.
if [[ "${AKARI_TEST_LOCK_PARENT:-}" != "$PPID" ]]; then
  lock_file='/run/akari/test.lock'
  lock_dir="${lock_file%/*}"
  if [[ -L "$lock_dir" || -L "$lock_file" ]]; then
    echo 'Refusing symlink test lock path.' >&2
    exit 1
  fi
  mkdir -p -m 0700 -- "$lock_dir"
  chmod 0700 -- "$lock_dir"
  umask 077
  exec 9>"$lock_file"
  umask 022
  flock 9
fi
if [[ "${1:-}" != --service-stopped ]]; then
  systemctl stop akari-test.service || true
fi
# ExecStopPost must not stop its own service: systemctl would wait for this
# very process. Start SDDM before disarming the independent recovery timer.
systemctl start sddm.service
systemctl is-active --quiet sddm.service
systemctl stop akari-restore.timer || true
umask 022
run_dir="$(readlink -f "$test_root/current-run")"
if [[ -n "$run_dir" && ! -L "$run_dir" && -d "$run_dir" && -f "$run_dir/started-at" && ! -L "$run_dir/started-at" ]]; then
  started_at="$(<"$run_dir/started-at")"
  if [[ "$started_at" =~ ^[0-9]+$ ]] && [[ ! -L "$run_dir/journal.log" && ! -L "$run_dir/restore.log" ]]; then
    journalctl -u akari-test.service -u sddm.service \
      --since="@$started_at" --no-pager -o short-iso-precise \
      > "$run_dir/journal.log"
    printf 'Restored SDDM at %s; service result: %s\n' \
      "$(date --iso-8601=seconds)" "${SERVICE_RESULT:-manual}" >> "$run_dir/restore.log"
  fi
fi
printf 'SDDM restored. Test logs: %s\n' "$run_dir"
