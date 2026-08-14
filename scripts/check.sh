#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_dir/.." && pwd)"

python3 -m json.tool "$root/runtime.lock.json" >/dev/null
python3 - "$root/packaging/edge-wasix/wasmer.toml" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as stream:
    manifest = tomllib.load(stream)
assert manifest["package"]["entrypoint"] == "edge"
assert manifest["module"][0]["source"] == "./edgejs.wasm"
assert "fs" not in manifest
assert {command["name"] for command in manifest["command"]} == {"edge", "edgejs", "node"}
PY
python3 -m py_compile \
  "$root/scripts/generate-manifest.py" \
  "$root/scripts/generate-rust-notices.py" \
  "$root/scripts/verify-manifest.py"
bash -n "$root"/scripts/*.sh

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$root"/scripts/*.sh
else
  printf 'warning: shellcheck not installed; skipping shell lint\n' >&2
fi

grep -Fxq '0.1.0-dev.1' "$root/VERSION"
grep -Fq '"version": "0.1.0-dev.1"' "$root/runtime.lock.json"
grep -Fq 'version = "0.1.0-dev.1"' "$root/packaging/edge-wasix/wasmer.toml"
if grep -Eq '^\[fs\]' "$root/packaging/edge-wasix/wasmer.toml"; then
  printf 'error: package manifest must not declare ambient filesystem mounts\n' >&2
  exit 1
fi
if grep -Eq 'quickjs-wasm/(etc|pnpm)|wasmer/edgejs@' "$root/packaging/edge-wasix/wasmer.toml"; then
  printf 'error: package manifest contains a broken or remote package reference\n' >&2
  exit 1
fi

printf 'Static checks passed.\n'
