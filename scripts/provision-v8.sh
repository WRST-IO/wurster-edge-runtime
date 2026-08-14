#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$script_dir/lib.sh"

root="$(repo_root)"
lock="$root/runtime.lock.json"
target="$(host_target)"
version="$(lock_value "$lock" toolchain.v8.version)"
download_root="${WURSTER_BUILD_DOWNLOAD_ROOT:-$root/build/downloads}"
v8_root="${WURSTER_V8_ROOT:-$root/build/v8-$version-$target}"
archive="$download_root/v8-$target.tar.xz"
expected_sha256="$(lock_value "$lock" "toolchain.v8.targets.$target.sha256")"
url="$(lock_value "$lock" "toolchain.v8.targets.$target.url")"

for command in curl install mktemp tar; do
  require_command "$command"
done

if [[ -f "$v8_root/include/v8.h" && -f "$v8_root/lib/libv8.a" ]]; then
  printf '%s\n' "$v8_root"
  exit 0
fi
if [[ -e "$v8_root" ]]; then
  printf 'error: incomplete V8 directory exists: %s\n' "$v8_root" >&2
  exit 1
fi

install -d "$download_root"
if [[ ! -f "$archive" ]]; then
  partial="$archive.partial"
  curl --fail --location --proto '=https' --tlsv1.2 --retry 3 \
    --output "$partial" "$url"
  test "$(sha256_file "$partial")" = "$expected_sha256"
  mv "$partial" "$archive"
fi
test "$(sha256_file "$archive")" = "$expected_sha256"

extract_root="$(mktemp -d "$root/build/v8-extract.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$extract_root"
  return "$status"
}
trap cleanup EXIT
tar -xJf "$archive" -C "$extract_root"
if [[ ! -f "$extract_root/include/v8.h" || ! -f "$extract_root/lib/libv8.a" ]]; then
  printf 'error: pinned V8 archive has no expected headers/static library\n' >&2
  exit 1
fi
mv "$extract_root" "$v8_root"
trap - EXIT
printf '%s\n' "$v8_root"
