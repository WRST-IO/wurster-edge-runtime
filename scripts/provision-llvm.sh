#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$script_dir/lib.sh"

root="$(repo_root)"
lock="$root/runtime.lock.json"
download_root="${WURSTER_BUILD_DOWNLOAD_ROOT:-$root/build/downloads}"
target="$(host_target)"
llvm_root="${WURSTER_LLVM_ROOT:-$root/build/llvm-22-$target}"
archive="$download_root/llvm-$target.tar.xz"
expected_sha256="$(lock_value "$lock" "toolchain.llvm.targets.$target.sha256")"
url="$(lock_value "$lock" "toolchain.llvm.targets.$target.url")"

for command in curl install mktemp tar; do
  require_command "$command"
done

if [[ -x "$llvm_root/bin/llvm-config" ]]; then
  printf '%s\n' "$llvm_root"
  exit 0
fi
if [[ -e "$llvm_root" ]]; then
  printf 'error: incomplete LLVM directory exists: %s\n' "$llvm_root" >&2
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

extract_root="$(mktemp -d "$root/build/llvm-extract.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$extract_root"
  return "$status"
}
trap cleanup EXIT
tar -xJf "$archive" -C "$extract_root"
if [[ ! -x "$extract_root/bin/llvm-config" ]]; then
  printf 'error: pinned LLVM archive has no bin/llvm-config\n' >&2
  exit 1
fi
mv "$extract_root" "$llvm_root"
trap - EXIT
printf '%s\n' "$llvm_root"
