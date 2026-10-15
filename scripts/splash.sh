#!/usr/bin/env bash

# Both VT launchers call this before execing their compositor. The renderer is
# a direct child of the launcher, so parent death and signal cleanup have one
# owner. wait is the release acknowledgement, including the failure path.
akari_show_splash() {
  local splash_pid=''
  local splash_owner="$BASHPID"
  local splash_status=0
  trap 'if [[ -n "$splash_pid" ]]; then kill "$splash_pid" 2>/dev/null || true; wait "$splash_pid" 2>/dev/null || true; fi' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  AKARI_SPLASH_PARENT_PID="$splash_owner" "$AKARI_SPLASH_BIN" kms &
  splash_pid=$!
  wait "$splash_pid" || splash_status=$?
  splash_pid=''
  trap - EXIT INT TERM HUP
  printf 'event=splash_finished status=%s\n' "$splash_status"
  return "$splash_status"
}
