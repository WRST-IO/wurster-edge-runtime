#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$script_dir/lib.sh"

root="$(repo_root)"
lock="$root/runtime.lock.json"
source_root="${1:-$root/build/src}"
bundle_name="wurster-edge-runtime-linux-amd64"
output_root="$root/out"
bundle="$output_root/$bundle_name"
archive="$output_root/$bundle_name.tar.gz"
source_date_epoch="$(lock_value "$lock" toolchain.source_date_epoch)"

require_linux_amd64
for command in find git install python3 sha256sum tar gzip; do
  require_command "$command"
done

edge_bin="$source_root/edgejs/build-edge/edge"
edge_wasm="$source_root/edgejs/build-wasix/edgejs.wasm"
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
  "$bundle/LICENSES/edgejs" "$bundle/LICENSES/wasmer"
install -m 0755 "$edge_bin" "$bundle/bin/edge"
install -m 0755 "$wasmer_bin" "$bundle/bin/wasmer"
install -m 0644 "$edge_wasm" "$bundle/share/edge-wasix/edgejs.wasm"
install -m 0644 "$root/packaging/edge-wasix/wasmer.toml" \
  "$bundle/share/edge-wasix/wasmer.toml"
install -m 0644 "$root/packaging/BUNDLE_README.md" "$bundle/README.md"
install -m 0644 "$lock" "$bundle/runtime.lock.json"
install -m 0644 "$root/packaging/NOTICE.md" "$bundle/LICENSES/NOTICE.md"

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
  --patch-root "$root/patches"

(cd "$output_root" && \
  tar --sort=name --mtime="@$source_date_epoch" --owner=0 --group=0 --numeric-owner \
    -cf - "$bundle_name" | gzip -n > "$archive")
(cd "$output_root" && sha256sum "$(basename "$archive")" > SHA256SUMS)

printf 'Bundle: %s\nArchive: %s\n' "$bundle" "$archive"
