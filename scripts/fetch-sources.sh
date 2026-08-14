#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$script_dir/lib.sh"

root="$(repo_root)"
lock="$root/runtime.lock.json"
source_root="${1:-$root/build/src}"

require_command git
require_command python3

edge_repository="$(lock_value "$lock" sources.edgejs.repository)"
edge_commit="$(lock_value "$lock" sources.edgejs.commit)"
wasmer_repository="$(lock_value "$lock" sources.wasmer.repository)"
wasmer_commit="$(lock_value "$lock" sources.wasmer.commit)"
napi_commit="$(lock_value "$lock" sources.napi.commit)"

checkout_pinned_repo "$edge_repository" "$edge_commit" "$source_root/edgejs"
checkout_pinned_repo "$wasmer_repository" "$wasmer_commit" "$source_root/wasmer"

git -C "$source_root/edgejs" -c protocol.version=2 submodule update \
  --init --recursive --depth 1 \
  napi ssl-certs deps/libuv-wasix deps/openssl-wasix
git -C "$source_root/wasmer" -c protocol.version=2 submodule update \
  --init --recursive --depth 1 lib/napi

edge_napi="$(git -C "$source_root/edgejs" rev-parse HEAD:napi)"
wasmer_napi="$(git -C "$source_root/wasmer" rev-parse HEAD:lib/napi)"
if [[ "$edge_napi" != "$napi_commit" || "$wasmer_napi" != "$napi_commit" ]]; then
  printf 'error: N-API ABI lock mismatch: lock=%s edge=%s wasmer=%s\n' \
    "$napi_commit" "$edge_napi" "$wasmer_napi" >&2
  exit 1
fi

printf 'Pinned sources ready in %s\n' "$source_root"
