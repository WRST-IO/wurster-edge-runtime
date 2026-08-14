#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$script_dir/lib.sh"

root="$(repo_root)"
bundle="${1:-$root/out/wurster-edge-runtime-linux-amd64}"
bundle="$(cd "$bundle" && pwd)"
edge="$bundle/bin/edge"
wasmer="$bundle/bin/wasmer"
package="$bundle/share/edge-wasix"

require_linux_amd64
for command in env file grep ln mktemp python3 strace; do
  require_command "$command"
done

for artifact in "$edge" "$wasmer" "$package/edgejs.wasm" "$package/wasmer.toml"; do
  if [[ ! -f "$artifact" ]]; then
    printf 'error: bundle artifact missing: %s\n' "$artifact" >&2
    exit 1
  fi
done

file "$edge" | grep -q 'ELF 64-bit.*x86-64'
file "$wasmer" | grep -q 'ELF 64-bit.*x86-64'

version_detail="$($wasmer --version -v 2>&1)"
printf '%s\n' "$version_detail"
grep -Eq '(^|[ ,])napi_v10([ ,]|$)' <<<"$version_detail"
grep -Eq '(^|[ ,])napi_extension_wasmer_v0([ ,]|$)' <<<"$version_detail"

if grep -Eq 'quickjs-wasm/(etc|pnpm)|wasmer/edgejs@|registry|cdn' "$package/wasmer.toml"; then
  printf 'error: WASIX manifest contains a forbidden remote or missing-path reference\n' >&2
  exit 1
fi
if grep -Eq '^\[fs\]' "$package/wasmer.toml"; then
  printf 'error: WASIX manifest must not add ambient filesystem mounts\n' >&2
  exit 1
fi

python3 "$script_dir/verify-manifest.py" "$bundle"

run_root="$(mktemp -d "${TMPDIR:-/tmp}/wurster-edge-verify.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$run_root"
  return "$status"
}
trap cleanup EXIT

install -d "$run_root/sandbox" "$run_root/fake-bin"
printf '%s\n' 'host-secret-must-not-be-visible' > "$run_root/host-secret"
ln -s ../host-secret "$run_root/sandbox/escape-link"

pushd "$run_root/sandbox" >/dev/null
version_output="$(
  HOME="$run_root/host-home-must-not-leak" \
  WURSTER_EDGE_BIN="$edge" \
  WASMER_BIN="$wasmer" \
  EDGE_WASMER_PACKAGE="$package" \
  "$edge" --safe -e 'console.log(process.version)'
)"
grep -Eq '^v[0-9]+' <<<"$version_output"

fs_output="$(
  HOME="$run_root/host-home-must-not-leak" \
  WURSTER_EDGE_BIN="$edge" \
  WASMER_BIN="$wasmer" \
  EDGE_WASMER_PACKAGE="$package" \
  "$edge" --safe -e '
    const fs = require("node:fs");
    fs.mkdirSync("dist", { recursive: true });
    fs.writeFileSync("dist/out.txt", "pigsty-ok");
    console.log(fs.readFileSync("dist/out.txt", "utf8"));
    console.log("HOME=" + process.env.HOME);
  '
)"
grep -Fxq 'pigsty-ok' <<<"$fs_output"
grep -Fxq 'HOME=/tmp' <<<"$fs_output"
test "$(<dist/out.txt)" = 'pigsty-ok'

isolation_output="$(
  WURSTER_EDGE_BIN="$edge" \
  WASMER_BIN="$wasmer" \
  EDGE_WASMER_PACKAGE="$package" \
  "$edge" --safe -e '
    const fs = require("node:fs");
    for (const candidate of ["../host-secret", "escape-link"]) {
      let blocked = false;
      try { fs.readFileSync(candidate, "utf8"); }
      catch (error) { blocked = true; }
      if (!blocked) throw new Error(`filesystem escape: ${candidate} was readable`);
    }
    console.log("outside-blocked");
  '
)"
grep -Fxq 'outside-blocked' <<<"$isolation_output"
popd >/dev/null

# A poisoned PATH proves that the actual safe start does not delegate to a host
# Node executable.
printf '%s\n' '#!/usr/bin/env sh' 'printf host-node-used > "$HOST_NODE_MARKER"' 'exit 97' \
  > "$run_root/fake-bin/node"
chmod 0755 "$run_root/fake-bin/node"
pushd "$run_root/sandbox" >/dev/null
PATH="$run_root/fake-bin:/usr/bin:/bin" \
HOST_NODE_MARKER="$run_root/host-node-marker" \
WASMER_BIN="$wasmer" \
EDGE_WASMER_PACKAGE="$package" \
"$edge" --safe -e 'console.log("no-host-node")' | grep -Fxq 'no-host-node'
popd >/dev/null
test ! -e "$run_root/host-node-marker"

pushd "$run_root/sandbox" >/dev/null
strace -f -qq -e trace=execve -o "$run_root/execve.trace" \
  env WASMER_BIN="$wasmer" EDGE_WASMER_PACKAGE="$package" \
  "$edge" --safe -e 'console.log("exec-boundary-ok")' \
  | grep -Fxq 'exec-boundary-ok'
popd >/dev/null
grep -Fq "execve(\"$wasmer\"" "$run_root/execve.trace"
if grep -Eq 'execve\("[^"]*/(node|nodejs|sh|bash)"' "$run_root/execve.trace"; then
  printf 'error: safe mode executed a host Node or shell binary\n' >&2
  grep -E 'execve\("[^"]*/(node|nodejs|sh|bash)"' "$run_root/execve.trace" >&2
  exit 1
fi

# Intercept the launcher-to-Wasmer boundary. This guards the Wurster patch even
# when the surrounding CI host itself has network access.
printf '%s\n' \
  '#!/usr/bin/env sh' \
  'if [ "${1:-}" = "--version" ]; then' \
  '  printf "%s\n" "wasmer 7.2.1" "features: napi_v10 napi_extension_wasmer_v0"' \
  '  exit 0' \
  'fi' \
  'printf "%s\n" "$@" > "$FAKE_WASMER_LOG"' \
  > "$run_root/fake-wasmer"
chmod 0755 "$run_root/fake-wasmer"
FAKE_WASMER_LOG="$run_root/wasmer-argv" \
WASMER_BIN="$run_root/fake-wasmer" \
EDGE_WASMER_PACKAGE="$package" \
"$edge" --safe -e 'console.log("captured")'
grep -Fxq "$package" "$run_root/wasmer-argv"
grep -Fxq -- '--llvm' "$run_root/wasmer-argv"
grep -Fxq -- '--experimental-napi' "$run_root/wasmer-argv"
grep -Fxq -- '--volume=.' "$run_root/wasmer-argv"
grep -Fxq -- 'HOME=/tmp' "$run_root/wasmer-argv"
if grep -Fxq -- '--net' "$run_root/wasmer-argv"; then
  printf 'error: safe mode granted network access\n' >&2
  exit 1
fi

printf '%s\n' \
  "[ok] process.version: $version_output" \
  '[ok] node:fs read/write: pigsty-ok' \
  '[ok] guest HOME: /tmp' \
  '[ok] parent and symlink filesystem escapes blocked' \
  '[ok] no host Node or shell fallback (PATH poison + execve trace)' \
  '[ok] local package and network-disabled safe command' \
  'All Wurster Edge Runtime smoke tests passed.'
