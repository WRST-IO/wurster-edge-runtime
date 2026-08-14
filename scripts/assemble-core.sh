#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$script_dir/lib.sh"

root="$(repo_root)"
lock="$root/runtime.lock.json"
source_root="${1:-$root/build/src}"
edge_wasm="${2:-$source_root/edgejs/build-wasix/edgejs.wasm}"
output_root="$root/out"
bundle_name="wurster-edge-runtime-core"
bundle="$output_root/$bundle_name"
archive="$output_root/$bundle_name.tar.gz"
source_date_epoch="$(lock_value "$lock" toolchain.source_date_epoch)"

for command in find gzip install python3 tar; do
  require_command "$command"
done
if [[ ! -f "$edge_wasm" ]]; then
  printf 'error: missing tested WASIX guest: %s\n' "$edge_wasm" >&2
  exit 1
fi
if [[ -e "$bundle" || -e "$archive" ]]; then
  printf 'error: refusing to overwrite core output: %s\n' "$bundle" >&2
  exit 1
fi

install -d "$bundle/LICENSES/edgejs" "$bundle/LICENSES/wasmer" "$bundle/LICENSES/wurster"
install -m 0644 "$edge_wasm" "$bundle/wurster-edgejs.wasm"
install -m 0644 "$lock" "$bundle/runtime.lock.json"
install -m 0644 "$root/packaging/NOTICE.md" "$bundle/LICENSES/NOTICE.md"
install -m 0644 "$root/LICENSE" "$bundle/LICENSES/wurster/LICENSE"

while IFS= read -r license_file; do
  relative="${license_file#"$source_root/edgejs/"}"
  destination="$bundle/LICENSES/edgejs/$relative"
  install -d "$(dirname "$destination")"
  install -m 0644 "$license_file" "$destination"
done < <(find "$source_root/edgejs" -type f \
  \( -iname 'LICENSE' -o -iname 'LICENSE.*' -o -iname 'COPYING' -o -iname 'COPYING.*' \) \
  -not -path '*/build-*/*' -print | sort)

while IFS= read -r license_file; do
  relative="${license_file#"$source_root/wasmer/"}"
  destination="$bundle/LICENSES/wasmer/$relative"
  install -d "$(dirname "$destination")"
  install -m 0644 "$license_file" "$destination"
done < <(find "$source_root/wasmer" -type f \
  \( -iname 'LICENSE' -o -iname 'LICENSE.*' -o -iname 'COPYING' -o -iname 'COPYING.*' \) \
  -not -path '*/target/*' -print | sort)

python3 "$script_dir/generate-rust-notices.py" \
  --manifest-path "$source_root/wasmer/lib/cli/Cargo.toml" \
  --output "$bundle/LICENSES/wasmer-rust-dependencies.md"

python3 "$script_dir/generate-manifest.py" \
  --bundle "$bundle" \
  --lock "$lock" \
  --patch-root "$root/patches" \
  --target core

(cd "$output_root" && \
  tar --sort=name --mtime="@$source_date_epoch" --owner=0 --group=0 --numeric-owner \
    -cf - "$bundle_name" | gzip -n > "$archive")
archive_digest="$(sha256_file "$archive")"
printf '%s  %s\n' "$archive_digest" "$(basename "$archive")" > "$archive.sha256"

printf 'Core: %s\nArchive: %s\nChecksum: %s\n' "$bundle" "$archive" "$archive.sha256"
