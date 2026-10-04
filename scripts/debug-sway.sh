#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib.sh"
repo_root="$(mozais_repo_root)"
mozais_run_dev_cli "$repo_root" run sway "$@"
