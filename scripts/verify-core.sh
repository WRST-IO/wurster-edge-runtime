#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_dir/.." && pwd)"
bundle="${1:-$root/out/wurster-edge-runtime-core}"

test -f "$bundle/wurster-edgejs.wasm"
test -f "$bundle/manifest.json"
test -f "$bundle/runtime.lock.json"
test -d "$bundle/LICENSES"
test ! -e "$bundle/bin"

python3 "$script_dir/verify-manifest.py" "$bundle"
python3 - "$bundle/manifest.json" <<'PY'
import hashlib
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
bundle = manifest_path.parent
assert manifest["name"] == "wurster-edge-runtime"
assert manifest["target"] == "core"
assert manifest["runtime_contract"]["host_kind"] == "portable-wasix-guest"
assert manifest["wasix_guest"]["path"] == "wurster-edgejs.wasm"
actual = hashlib.sha256((bundle / "wurster-edgejs.wasm").read_bytes()).hexdigest()
assert manifest["wasix_guest"]["sha256"] == actual
PY

printf 'Core WASIX guest and compatibility manifest verified.\n'
