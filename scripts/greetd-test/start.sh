#!/usr/bin/env bash
set -euo pipefail

test_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$EUID" -ne 0 ]]; then
  printf 'Run with sudo: sudo %s/start.sh\n' "$test_root" >&2
  exit 1
fi

exec 9>/run/lock/mozais-test.lock
flock -n 9 || { echo 'Another test setup is running.' >&2; exit 1; }
IFS=: read -r log_user _ log_uid _ _ _ _ < <(getent passwd "${SUDO_USER:-root}")
log_root="${MOZAIS_TEST_LOG_DIR:-/var/tmp/mozais-greetd-test-$log_uid}"
if [[ "$log_root" != /* ]]; then
  echo 'MOZAIS_TEST_LOG_DIR must be an absolute path.' >&2
  exit 1
fi
umask 022
run_dir="$log_root/$(date +%Y%m%d-%H%M%S)-$$"
# Keep diagnostics outside the installation and readable without root or
# membership in the caller's group, including tests started directly as root.
install -d -o "$log_user" -g greeter -m 0755 "$log_root" "$run_dir"
ln -sfn "$run_dir" "$log_root/latest"
exec > >(tee -a "$run_dir/start.log") 2>&1
trap 'status=$?; printf "Startup failed at line %s (status %s).\n" "$LINENO" "$status"; exit "$status"' ERR
printf 'Test logs: %s\nStartup log: %s/start.log\n' "$run_dir" "$run_dir"

# sudo may give the command a PTY. SUDO_TTY identifies the invoking console.
terminal="${SUDO_TTY:-$(tty 2>/dev/null || true)}"
printf 'Started at %s; caller terminal: %s\n' "$(date --iso-8601=seconds)" "$terminal"
case "$terminal" in
  /dev/tty[2-6]) ;;
  *) echo 'Log out of the desktop, log in on tty3, and start the test there.'; exit 1 ;;
esac

for session in $(loginctl list-sessions --no-legend --no-pager | awk '{print $1}'); do
  properties="$(loginctl show-session "$session" -p Class -p Type -p State)"
  printf 'Session %s:\n%s\n' "$session" "$properties"
  if [[ "$properties" == *'Class=user'* && "$properties" != *'State=closing'* ]] &&
     [[ "$properties" == *'Type=wayland'* || "$properties" == *'Type=x11'* ]]; then
    echo "Desktop session $session is still running. Log out before testing."
    exit 1
  fi
done

if [[ "$(systemctl get-default)" != graphical.target ]] ||
   [[ "$(systemctl is-enabled sddm.service)" != enabled ]] ||
   [[ "$(readlink -f /etc/systemd/system/display-manager.service)" != /usr/lib/systemd/system/sddm.service ]]; then
  echo 'Expected graphical.target with SDDM enabled; boot configuration differs.'
  exit 1
fi
for unit in greetd.service mozais-test.service mozais-restore.timer; do
  if systemctl is-active --quiet "$unit"; then
    echo "$unit is already active. Restore the previous test first."
    exit 1
  fi
done
test -x "$test_root/frontend/greeter"
test -x "$test_root/backend"

scale="${MOZAIS_TEST_SCALE:-1}"
if [[ ! "$scale" =~ ^[0-9]+([.][0-9]+)?$ ]] || ! awk "BEGIN { exit !($scale > 0) }"; then
  echo 'MOZAIS_TEST_SCALE must be a positive number.'
  exit 1
fi
install -d -o greeter -g greeter -m 0755 "$run_dir/greeter"
printf 'output * scale %s\ninclude %s/sway.conf\n' "$scale" "$test_root" > "$run_dir/sway.conf"
if ! runuser -u greeter -- test -w "$run_dir/greeter"; then
  echo 'The greeter cannot access the log directory. Choose a path outside a private home directory.'
  exit 1
fi
date +%s > "$run_dir/started-at"
ln -sfn "$run_dir" "$log_root/current"
ln -sfn "$run_dir" "$test_root/current-run"

# Recovery belongs to systemd, so it survives this shell and runs after service
# exit as well as on the deadline. Arm it before touching the display manager.
systemd-run --unit=mozais-restore --collect \
  --on-active=10m --timer-property=AccuracySec=1s "$test_root/restore.sh"
trap 'status=$?; trap - EXIT; if (( status != 0 )); then "$test_root/restore.sh"; fi' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
systemctl is-active --quiet mozais-restore.timer
systemctl stop sddm.service
systemd-run --unit=mozais-test --collect \
  --property=Type=exec \
  --property=Conflicts=getty@tty1.service \
  --property=After=systemd-user-sessions.service \
  --property=IgnoreSIGPIPE=no \
  --property=SendSIGHUP=yes \
  --property=KeyringMode=shared \
  --property=TimeoutStopSec=30s \
  --property="ExecStopPost=$test_root/restore.sh --service-stopped" \
  /usr/bin/greetd --config "$test_root/greetd.toml"
echo "Mozais is on tty1; power actions call logind; output scale is $scale."
echo "Recovery runs after service exit or in 10 minutes. Logs: $run_dir"
echo "To restore sooner: Ctrl+Alt+F3, then sudo $test_root/restore.sh"
