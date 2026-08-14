#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$script_dir/lib.sh"

root="$(repo_root)"
edge_dir="${1:-$root/build/src/edgejs}"

if [[ ! -d "$edge_dir/.git" ]]; then
  printf 'error: Edge source checkout not found: %s\n' "$edge_dir" >&2
  exit 1
fi

while IFS= read -r patch_file; do
  if git -C "$edge_dir" apply --check "$patch_file"; then
    git -C "$edge_dir" apply "$patch_file"
  elif git -C "$edge_dir" apply --reverse --check "$patch_file"; then
    printf 'Patch already applied: %s\n' "${patch_file#"$root/"}"
  else
    printf 'error: patch neither applies nor is already present: %s\n' "$patch_file" >&2
    exit 1
  fi
done < <(find "$root/patches/edge" -type f -name '*.patch' -print | sort)
