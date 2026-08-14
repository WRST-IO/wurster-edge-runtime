#!/usr/bin/env bash

set -euo pipefail

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

lock_value() {
  local lock_file="$1"
  local dotted_path="$2"
  python3 - "$lock_file" "$dotted_path" <<'PY'
import json
import sys

value = json.load(open(sys.argv[1], encoding="utf-8"))
for part in sys.argv[2].split("."):
    value = value[part]
if isinstance(value, (dict, list)):
    print(json.dumps(value, separators=(",", ":")))
else:
    print(value)
PY
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'error: required command not found: %s\n' "$1" >&2
    exit 1
  }
}

require_linux_amd64() {
  local kernel machine
  kernel="$(uname -s)"
  machine="$(uname -m)"
  if [[ "$kernel" != "Linux" || "$machine" != "x86_64" ]]; then
    printf 'error: supported build host is Linux x86_64, got %s %s\n' "$kernel" "$machine" >&2
    exit 1
  fi
}

require_darwin_arm64() {
  local kernel machine
  kernel="$(uname -s)"
  machine="$(uname -m)"
  if [[ "$kernel" != "Darwin" || "$machine" != "arm64" ]]; then
    printf 'error: supported build host is Darwin arm64, got %s %s\n' "$kernel" "$machine" >&2
    exit 1
  fi
}

require_darwin_amd64() {
  local kernel machine
  kernel="$(uname -s)"
  machine="$(uname -m)"
  if [[ "$kernel" != "Darwin" || "$machine" != "x86_64" ]]; then
    printf 'error: supported build host is Darwin x86_64, got %s %s\n' "$kernel" "$machine" >&2
    exit 1
  fi
}

host_target() {
  case "$(uname -s):$(uname -m)" in
    Linux:x86_64) printf '%s\n' linux-amd64 ;;
    Darwin:arm64) printf '%s\n' darwin-arm64 ;;
    Darwin:x86_64) printf '%s\n' darwin-amd64 ;;
    *)
      printf 'error: unsupported host: %s %s\n' "$(uname -s)" "$(uname -m)" >&2
      exit 1
      ;;
  esac
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

verify_v8_version() {
  local include_root="$1"
  local expected="$2"
  python3 - "$include_root/v8-version.h" "$expected" <<'PY'
import pathlib
import re
import sys

header = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
expected = tuple(int(part) for part in sys.argv[2].split("."))
names = ("V8_MAJOR_VERSION", "V8_MINOR_VERSION", "V8_BUILD_NUMBER", "V8_PATCH_LEVEL")
actual = tuple(int(re.search(rf"^#define {name} (\d+)$", header, re.MULTILINE).group(1)) for name in names)
if actual != expected:
    raise SystemExit(f"V8 header version mismatch: expected {expected}, found {actual}")
PY
}

checkout_pinned_repo() {
  local repository="$1"
  local commit="$2"
  local destination="$3"

  if [[ -d "$destination/.git" ]]; then
    local actual
    actual="$(git -C "$destination" rev-parse HEAD)"
    if [[ "$actual" != "$commit" ]]; then
      printf 'error: %s exists at %s, expected %s\n' "$destination" "$actual" "$commit" >&2
      exit 1
    fi
    return
  fi
  if [[ -e "$destination" ]]; then
    printf 'error: refusing to overwrite non-repository path: %s\n' "$destination" >&2
    exit 1
  fi

  install -d "$(dirname "$destination")"
  git init -q "$destination"
  git -C "$destination" remote add origin "$repository"
  git -C "$destination" fetch --depth 1 origin "$commit"
  git -C "$destination" checkout -q --detach FETCH_HEAD
  test "$(git -C "$destination" rev-parse HEAD)" = "$commit"
}
