#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$script_dir/lib.sh"

root="$(repo_root)"
lock="$root/runtime.lock.json"
source_root="${WURSTER_BUILD_SOURCE_ROOT:-$root/build/src}"
jobs="${JOBS:-4}"

require_linux_amd64
for command in bash cmake git make python3 cargo rustc wasixcc wasm-opt; do
  require_command "$command"
done

"$script_dir/fetch-sources.sh" "$source_root"
"$script_dir/apply-patches.sh" "$source_root"

edge_commit="$(lock_value "$lock" sources.edgejs.commit)"
wasmer_commit="$(lock_value "$lock" sources.wasmer.commit)"
napi_commit="$(lock_value "$lock" sources.napi.commit)"
source_date_epoch="$(lock_value "$lock" toolchain.source_date_epoch)"
export SOURCE_DATE_EPOCH="$source_date_epoch"
export TZ=UTC
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

test "$(git -C "$source_root/edgejs" rev-parse HEAD)" = "$edge_commit"
test "$(git -C "$source_root/wasmer" rev-parse HEAD)" = "$wasmer_commit"
test "$(git -C "$source_root/edgejs" rev-parse HEAD:napi)" = "$napi_commit"
test "$(git -C "$source_root/wasmer" rev-parse HEAD:lib/napi)" = "$napi_commit"

v8_root="$("$script_dir/provision-v8.sh")"
export NAPI_V8_INCLUDE_DIR="$v8_root/include"
export NAPI_V8_LIBRARY="$v8_root/lib/libv8.a"
make -C "$source_root/edgejs" build CMAKE_BUILD_TYPE=Release JOBS="$jobs"
make -C "$source_root/edgejs" build-wasix CMAKE_BUILD_TYPE=Release JOBS="$jobs"
make -C "$source_root/edgejs" validate-wasix-imports

llvm_root="$("$script_dir/provision-llvm.sh")"
PATH="$llvm_root/bin:$PATH" make -C "$source_root/wasmer" build-wasmer \
  ENABLE_CRANELIFT=1 \
  ENABLE_SINGLEPASS=1 \
  ENABLE_LLVM=1 \
  ENABLE_V8=0 \
  ENABLE_NAPI_V8=1

"$script_dir/assemble-bundle.sh" "$source_root" linux-amd64
"$script_dir/verify-bundle.sh" "$root/out/wurster-edge-runtime-linux-amd64"
