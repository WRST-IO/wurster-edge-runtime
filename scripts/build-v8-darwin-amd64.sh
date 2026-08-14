#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$script_dir/lib.sh"

root="$(repo_root)"
lock="$root/runtime.lock.json"
output="${1:-$root/build/v8-$(lock_value "$lock" toolchain.v8.version)-darwin-amd64}"
work_root="${WURSTER_V8_SOURCE_ROOT:-$root/build/v8-source-darwin-amd64}"
builder_root="$work_root/builder"
depot_root="$work_root/depot_tools"
checkout_root="$work_root/checkout"
v8_root="$checkout_root/v8"
jobs="${JOBS:-4}"

require_darwin_amd64
for command in git install ninja python3; do
  require_command "$command"
done

if [[ -f "$output/include/v8.h" && -f "$output/lib/libv8.a" ]]; then
  exit 0
fi
if [[ -e "$output" ]]; then
  printf 'error: incomplete V8 output exists: %s\n' "$output" >&2
  exit 1
fi

builder_repository="$(lock_value "$lock" sources.v8_custom_builds.repository)"
builder_commit="$(lock_value "$lock" sources.v8_custom_builds.commit)"
depot_repository="$(lock_value "$lock" sources.depot_tools.repository)"
depot_commit="$(lock_value "$lock" sources.depot_tools.commit)"
v8_commit="$(lock_value "$lock" sources.v8.commit)"

checkout_pinned_repo "$builder_repository" "$builder_commit" "$builder_root"
checkout_pinned_repo "$depot_repository" "$depot_commit" "$depot_root"
install -d "$checkout_root"

export PATH="$PATH:$depot_root"
export DEPOT_TOOLS_UPDATE=0
export DEPOT_TOOLS_METRICS=0

if [[ ! -d "$v8_root/.git" ]]; then
  (
    cd "$checkout_root"
    fetch v8
  )
fi

git -C "$v8_root" fetch origin "$v8_commit"
git -C "$v8_root" checkout --detach "$v8_commit"
(
  cd "$checkout_root"
  gclient sync --with_branch_heads --with_tags --nohooks --revision "v8@$v8_commit"
)
test "$(git -C "$v8_root" rev-parse HEAD)" = "$v8_commit"
python3 "$v8_root/build/util/lastchange.py" -o "$v8_root/build/util/LASTCHANGE"

while IFS= read -r patch; do
  if git -C "$v8_root" apply --reverse --check "$patch" >/dev/null 2>&1; then
    continue
  fi
  git -C "$v8_root" apply --check "$patch"
  git -C "$v8_root" apply "$patch"
done < <(find "$builder_root/patches" -type f -name '*.patch' -print | sort)

(
  cd "$v8_root"
  gn gen out/wurster-release --args='is_debug=false
v8_symbol_level=0
symbol_level=0
is_component_build=false
is_official_build=false
use_custom_libcxx=false
use_custom_libcxx_for_host=false
use_sysroot=false
use_glib=false
is_clang=false
v8_expose_symbols=true
v8_optimized_debug=false
v8_enable_sandbox=false
v8_enable_i18n_support=true
icu_use_data_file=false
v8_enable_gdbjit=false
v8_use_external_startup_data=false
treat_warnings_as_errors=false
v8_enable_fast_mksnapshot=true
v8_enable_handle_zapping=false
v8_enable_pointer_compression=true
target_cpu="x64"
v8_target_cpu="x64"
target_os="mac"'
  ninja -C out/wurster-release -j "$jobs" wee8
)

stage="$work_root/dist"
if [[ -e "$stage" ]]; then
  printf 'error: refusing to overwrite V8 staging directory: %s\n' "$stage" >&2
  exit 1
fi
install -d "$stage/include/wasm-c-api" "$stage/lib"
cp -R "$v8_root/include/." "$stage/include/"
find "$stage/include" -type f ! -name '*.h' -delete
install -m 0644 "$v8_root/third_party/wasm-api/wasm.h" \
  "$stage/include/wasm-c-api/wasm.h"
install -m 0644 "$v8_root/out/wurster-release/obj/libwee8.a" "$stage/lib/libv8.a"
mv "$stage" "$output"

test -f "$output/include/v8.h"
test -f "$output/lib/libv8.a"
