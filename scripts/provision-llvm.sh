#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$script_dir/lib.sh"

root="$(repo_root)"
lock="$root/runtime.lock.json"
download_root="${WURSTER_BUILD_DOWNLOAD_ROOT:-$root/build/downloads}"
llvm_root="${WURSTER_LLVM_ROOT:-$root/build/llvm-22}"
archive="$download_root/llvm-linux-amd64.tar.xz"
expected_sha256="$(lock_value "$lock" toolchain.llvm.sha256)"
url="$(lock_value "$lock" toolchain.llvm.url)"

require_linux_amd64
for command in curl install mktemp sha256sum tar; do
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
  printf '%s  %s\n' "$expected_sha256" "$partial" | sha256sum --check --status
  mv "$partial" "$archive"
fi
printf '%s  %s\n' "$expected_sha256" "$archive" | sha256sum --check --status

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
