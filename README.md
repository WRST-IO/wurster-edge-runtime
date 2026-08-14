# WRST.IO Wurster Edge Runtime

This repository is the WRST.IO downstream fork and binary distribution of
[Edge.js](https://github.com/wasmerio/edgejs) for the Wurster Pigsty runtime.
It combines a small Wurster patch set with pinned Edge.js, Wasmer, shared N-API,
LLVM, and wasixcc revisions. It is not an official Wasmer or upstream Edge.js
release.

The result is one self-contained, offline-capable compatibility unit: a native
`edge` launcher, a matching NAPI-enabled Wasmer host, and the engine-free
Edge.js WASIX guest. See [FORK.md](FORK.md) for provenance, the exact downstream
delta, and the update policy.

## Supported release targets

| Release asset | Status | Host |
| --- | --- | --- |
| `wurster-edge-runtime-linux-amd64.tar.gz` | release-gated | Linux x86-64 |
| `wurster-edge-runtime-darwin-arm64.tar.gz` | release-gated | macOS Apple Silicon |
| Windows amd64 | blocked upstream | not published |
| macOS Intel | out of scope | not published |

“Release-gated” means the archive is published only if that exact bundle passes
the Pigsty safe-mode acceptance suite. Windows is not being labelled as
supported prematurely: the pinned Wasmer build explicitly disables the
required NAPI-V8 host feature on Windows and its matching V8 distribution has
no Windows artifact. Details and the unblock criteria are in
[docs/PLATFORMS.md](docs/PLATFORMS.md).

## Compatibility lock

| Component | Revision | Role |
| --- | --- | --- |
| Edge.js | `1ca99ab4ff3d74bf5940177eb007457612d398e3` | Node-compatible launcher and WASIX guest |
| Wasmer | `9b8fdf1720d6671a3de76aa8727f84536979104f` | Native WASIX sandbox host |
| N-API | `c5b66fb9f5b1b997d5bdd463dc1a80bb174d4730` | Identical ABI implementation in Edge and Wasmer |
| wasixcc | `v0.4.3`, sysroot `v2026-07-30.1` | WASIX guest compiler |
| LLVM | `22.1.8`, per-target checksums | Safe-mode execution backend |
| V8 host build | `11.9.2`, per-target checksums | Wasmer NAPI-V8 bridge |

`runtime.lock.json` is authoritative. Bundle versions are independent of Edge
and Wasmer versions and select one complete compatibility lock.

## Releases

Normal branch and pull-request runs retain Actions artifacts for CI inspection.
A Git tag matching `v$(cat VERSION)` runs every supported platform gate and,
only after all pass, creates a GitHub Release containing:

```text
wurster-edge-runtime-linux-amd64.tar.gz
wurster-edge-runtime-darwin-arm64.tar.gz
SHA256SUMS
```

These GitHub Release assets are the final binaries for Wurster consumers. The
release job downloads the already-tested archives, recomputes one authoritative
checksum file, verifies it, and publishes all assets together. A partial
platform release cannot be created by the workflow.

Maintainer steps, version invariants, and recovery behavior are documented in
[docs/RELEASING.md](docs/RELEASING.md).

## Bundle layout

```text
wurster-edge-runtime-<target>/
  bin/edge
  bin/wasmer
  share/edge-wasix/
    edgejs.wasm
    wasmer.toml
  manifest.json
  runtime.lock.json
  LICENSES/
  README.md
```

The WASIX guest is built once in the Linux job and reused byte-for-byte by the
macOS host build. Native `edge` and `wasmer` binaries are built and tested on
their target operating system.

## Build

CI is the supported reproducible build environment:

```bash
# Ubuntu 24.04 x86-64, with pinned wasixcc installed
./scripts/build-linux-amd64.sh

# macOS 15 Apple Silicon, using the guest produced above
./scripts/build-darwin-arm64.sh /path/to/edgejs.wasm
```

`make build` selects the supported target for the current host. Source
checkouts and compiler output stay under `build/`; final bundles are written to
`out/`. Building requires network access. Running the resulting bundle does
not.

## Wurster integration

Set absolute paths and enter the projected Wurst workspace before starting
Pigsty:

```bash
export WURSTER_EDGE_BIN=/opt/wurster-edge-runtime/bin/edge
export WASMER_BIN=/opt/wurster-edge-runtime/bin/wasmer
export EDGE_WASMER_PACKAGE=/opt/wurster-edge-runtime/share/edge-wasix
cd /path/to/projected/wurst
exec "$WURSTER_EDGE_BIN" --safe tool.js
```

Safe mode mounts only the current working directory. The downstream patch
removes Edge upstream's unconditional network grant, assigns guest
`HOME=/tmp`, and uses the bundled LLVM backend. There is no system-Node or
host-shell fallback. Wurster remains responsible for projecting `/wurst`,
read-only `/toolchain`, and writable `/tmp`.

See [SECURITY.md](SECURITY.md) for the boundary and known limitations and
[docs/ACCEPTANCE.md](docs/ACCEPTANCE.md) for the executable release gates.
