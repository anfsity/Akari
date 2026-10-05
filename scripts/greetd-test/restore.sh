#!/usr/bin/env bash
set -euo pipefail
test_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$EUID" -ne 0 ]]; then
  printf 'Run with sudo: sudo %s/restore.sh\n' "$test_root" >&2
  exit 1
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
if [[ -f "$run_dir/started-at" ]]; then
  journalctl -u akari-test.service -u sddm.service \
    --since="@$(cat "$run_dir/started-at")" --no-pager -o short-iso-precise \
    > "$run_dir/journal.log"
  printf 'Restored SDDM at %s; service result: %s\n' \
    "$(date --iso-8601=seconds)" "${SERVICE_RESULT:-manual}" >> "$run_dir/restore.log"
fi
printf 'SDDM restored. Test logs: %s\n' "$run_dir"
