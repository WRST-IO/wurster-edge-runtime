#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$script_dir/lib.sh"

root="$(repo_root)"
source_root="${1:-$root/build/src}"

apply_series() {
  local repository="$1"
  local patch_dir="$2"
  local patch_file

  if [[ ! -e "$repository/.git" ]]; then
    printf 'error: source checkout not found: %s\n' "$repository" >&2
    exit 1
  fi
  if [[ ! -d "$patch_dir" ]]; then
    return
  fi

  while IFS= read -r patch_file; do
    if git -C "$repository" apply --check "$patch_file"; then
      git -C "$repository" apply "$patch_file"
    elif git -C "$repository" apply --reverse --check "$patch_file"; then
      printf 'Patch already applied: %s\n' "${patch_file#"$root/"}"
    else
      printf 'error: patch neither applies nor is already present: %s\n' "$patch_file" >&2
      exit 1
    fi
  done < <(find "$patch_dir" -type f -name '*.patch' -print | sort)
}

apply_series "$source_root/edgejs" "$root/patches/edge"
apply_series "$source_root/wasmer" "$root/patches/wasmer"
apply_series "$source_root/edgejs/napi" "$root/patches/napi"
apply_series "$source_root/wasmer/lib/napi" "$root/patches/napi"
