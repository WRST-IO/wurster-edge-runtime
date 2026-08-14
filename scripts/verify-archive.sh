#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$script_dir/lib.sh"

archive="${1:?usage: verify-archive.sh ARCHIVE TARGET}"
target="${2:?usage: verify-archive.sh ARCHIVE TARGET}"
archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"
expected="wurster-edge-runtime-$target"
run_root="$(mktemp -d "${TMPDIR:-/tmp}/wurster-edge-archive.XXXXXX")"

cleanup() {
  local status=$?
  rm -rf -- "$run_root"
  return "$status"
}
trap cleanup EXIT

tar -xzf "$archive" -C "$run_root"
root_count="$(find "$run_root" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')"
bundle="$run_root/$expected"
if [[ "$root_count" -ne 1 || ! -d "$bundle" ]]; then
  printf 'error: archive must contain exactly top-level directory %s\n' "$expected" >&2
  exit 1
fi
"$script_dir/verify-bundle.sh" "$bundle"
