#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$script_dir/lib.sh"

root="$(repo_root)"
lock="$root/runtime.lock.json"
source_root="${1:-$root/build/src}"
target="${2:-$(host_target)}"
edge_wasm="${3:-$source_root/edgejs/build-wasix/edgejs.wasm}"
bundle_name="wurster-edge-runtime-$target"
output_root="$root/out"
bundle="$output_root/$bundle_name"
archive="$output_root/$bundle_name.tar.gz"
source_date_epoch="$(lock_value "$lock" toolchain.source_date_epoch)"

case "$target" in
  linux-amd64) require_linux_amd64 ;;
  darwin-arm64) require_darwin_arm64 ;;
  *) printf 'error: unsupported bundle target: %s\n' "$target" >&2; exit 1 ;;
esac
for command in find git gzip install python3; do
  require_command "$command"
done

if [[ "$target" == darwin-arm64 ]]; then
  require_command gtar
  tar_command="gtar"
else
  require_command tar
  tar_command="tar"
fi

edge_bin="$source_root/edgejs/build-edge/edge"
wasmer_bin="$source_root/wasmer/target/release/wasmer"
for artifact in "$edge_bin" "$edge_wasm" "$wasmer_bin"; do
  if [[ ! -f "$artifact" ]]; then
    printf 'error: missing build artifact: %s\n' "$artifact" >&2
    exit 1
  fi
done

if [[ -e "$bundle" || -e "$archive" ]]; then
  printf 'error: refusing to overwrite existing bundle output; move or remove %s first\n' "$bundle" >&2
  exit 1
fi

install -d "$bundle/bin" "$bundle/share/edge-wasix" \
  "$bundle/LICENSES/edgejs" "$bundle/LICENSES/wasmer" "$bundle/LICENSES/wurster"
install -m 0755 "$edge_bin" "$bundle/bin/edge"
install -m 0755 "$wasmer_bin" "$bundle/bin/wasmer"
install -m 0644 "$edge_wasm" "$bundle/share/edge-wasix/edgejs.wasm"
install -m 0644 "$root/packaging/edge-wasix/wasmer.toml" \
  "$bundle/share/edge-wasix/wasmer.toml"
install -m 0644 "$root/packaging/BUNDLE_README.md" "$bundle/README.md"
install -m 0644 "$lock" "$bundle/runtime.lock.json"
install -m 0644 "$root/packaging/NOTICE.md" "$bundle/LICENSES/NOTICE.md"
install -m 0644 "$root/LICENSE" "$bundle/LICENSES/wurster/LICENSE"

python3 "$script_dir/generate-rust-notices.py" \
  --manifest-path "$source_root/wasmer/lib/cli/Cargo.toml" \
  --output "$bundle/LICENSES/wasmer-rust-dependencies.md"

(cd "$bundle/share/edge-wasix" && "$bundle/bin/wasmer" package build --check .)

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

python3 "$script_dir/generate-manifest.py" \
  --bundle "$bundle" \
  --lock "$lock" \
  --patch-root "$root/patches" \
  --target "$target"

(cd "$output_root" && \
  "$tar_command" --sort=name --mtime="@$source_date_epoch" --owner=0 --group=0 --numeric-owner \
    -cf - "$bundle_name" | gzip -n > "$archive")
archive_digest="$(sha256_file "$archive")"
printf '%s  %s\n' "$archive_digest" "$(basename "$archive")" > "$archive.sha256"

printf 'Bundle: %s\nArchive: %s\nChecksum: %s\n' "$bundle" "$archive" "$archive.sha256"
