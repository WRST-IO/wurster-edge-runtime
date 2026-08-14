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
  "$root/scripts/create-deterministic-zip.py" \
  "$root/scripts/generate-rust-notices.py" \
  "$root/scripts/verify-release-set.py" \
  "$root/scripts/verify-manifest.py"
python3 - "$root" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
invalid = re.compile(r"\$(?!(?:env|script|global|local|private|using):)[A-Za-z_][A-Za-z0-9_]*:")
for path in sorted((root / "scripts").glob("*.ps1")):
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        match = invalid.search(line)
        if match:
            raise SystemExit(
                f"{path}:{number}: ambiguous PowerShell interpolation {match.group(0)!r}; "
                "use ${name}:"
            )
PY
bash -n "$root"/scripts/*.sh

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$root"/scripts/*.sh
else
  printf 'warning: shellcheck not installed; skipping shell lint\n' >&2
fi

python3 - "$root" <<'PY'
import json
import pathlib
import sys
import tomllib

root = pathlib.Path(sys.argv[1])
version = (root / "VERSION").read_text(encoding="utf-8").strip()
lock = json.loads((root / "runtime.lock.json").read_text(encoding="utf-8"))
with (root / "packaging/edge-wasix/wasmer.toml").open("rb") as stream:
    package = tomllib.load(stream)
assert version == lock["bundle"]["version"] == package["package"]["version"]
assert lock["bundle"]["targets"] == [
    "linux-amd64",
    "darwin-arm64",
    "darwin-amd64",
    "windows-amd64",
]
assert lock["bundle"]["reserved_targets"] == ["web", "ios-arm64", "android-arm64"]
assert lock["toolchain"]["v8"]["version"] == "13.6.233.17"
assert lock["toolchain"]["v8"]["upstream_asset_release"] == "11.9.7"
assert set(lock["toolchain"]["v8"]["targets"]) == set(lock["bundle"]["targets"])
assert set(lock["toolchain"]["wasmer_features"]) == set(lock["bundle"]["targets"])
assert lock["toolchain"]["v8"]["targets"]["darwin-amd64"]["build"] == "source"
assert lock["toolchain"]["v8"]["targets"]["darwin-amd64"]["v8_commit"] == lock["sources"]["v8"]["commit"]
assert lock["toolchain"]["v8"]["targets"]["darwin-amd64"]["builder_commit"] == lock["sources"]["v8_custom_builds"]["commit"]
assert lock["toolchain"]["v8"]["targets"]["darwin-amd64"]["depot_tools_commit"] == lock["sources"]["depot_tools"]["commit"]
assert lock["toolchain"]["v8"]["targets"]["windows-amd64"]["build"] == "source"
assert lock["toolchain"]["v8"]["targets"]["windows-amd64"]["v8_commit"] == lock["sources"]["v8"]["commit"]
assert lock["toolchain"]["v8"]["targets"]["windows-amd64"]["builder_commit"] == lock["sources"]["v8_custom_builds"]["commit"]
assert lock["toolchain"]["v8"]["targets"]["windows-amd64"]["depot_tools_commit"] == lock["sources"]["depot_tools"]["commit"]
assert "llvm" not in lock["toolchain"]["wasmer_features"]["windows-amd64"]
assert "v8" in lock["toolchain"]["wasmer_features"]["windows-amd64"]
PY
if grep -Eq '^\[fs\]' "$root/packaging/edge-wasix/wasmer.toml"; then
  printf 'error: package manifest must not declare ambient filesystem mounts\n' >&2
  exit 1
fi
if grep -Eq 'quickjs-wasm/(etc|pnpm)|wasmer/edgejs@' "$root/packaging/edge-wasix/wasmer.toml"; then
  printf 'error: package manifest contains a broken or remote package reference\n' >&2
  exit 1
fi

printf 'Static checks passed.\n'
