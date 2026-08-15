#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
archive="${1:?usage: verify-core-archive.sh ARCHIVE}"
archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"
run_root="$(mktemp -d "${TMPDIR:-/tmp}/wurster-edge-core.XXXXXX")"

cleanup() {
  local status=$?
  rm -rf -- "$run_root"
  return "$status"
}
trap cleanup EXIT

tar -xzf "$archive" -C "$run_root"
roots=("$run_root"/*)
if [[ "${#roots[@]}" -ne 1 || "$(basename "${roots[0]}")" != "wurster-edge-runtime-core" ]]; then
  printf 'error: core archive must contain exactly its named top-level directory\n' >&2
  exit 1
fi
"$script_dir/verify-core.sh" "${roots[0]}"
