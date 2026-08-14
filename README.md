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
| `wurster-edge-runtime-darwin-amd64.tar.gz` | release-gated | macOS Intel x86-64 |
| `wurster-edge-runtime-windows-amd64.zip` | release-gated | Windows x86-64 |
| `wurster-edge-runtime-core.tar.gz` | release-gated | portable WASIX guest |

“Release-gated” means the archive is published only if that exact bundle passes
the native Pigsty safe-mode acceptance suite. Windows and both native macOS
architectures are mandatory desktop targets. The WRST.IO patch set completes
the unfinished Windows paths in Edge's safe launcher, Wasmer's NAPI feature
selection, and the shared NAPI V8 resolver. Details are in
[docs/PLATFORMS.md](docs/PLATFORMS.md).

## Compatibility lock

| Component | Revision | Role |
| --- | --- | --- |
| Edge.js | `1ca99ab4ff3d74bf5940177eb007457612d398e3` | Node-compatible launcher and WASIX guest |
| Wasmer | `9b8fdf1720d6671a3de76aa8727f84536979104f` | Native WASIX sandbox host |
| N-API | `c5b66fb9f5b1b997d5bdd463dc1a80bb174d4730` | Identical ABI implementation in Edge and Wasmer |
| wasixcc | `v0.4.3`, sysroot `v2026-07-30.1` | WASIX guest compiler |
| LLVM | `22.1.8`, per-target checksums | Safe-mode execution backend |
| V8 host build | `13.6.233.17`, pinned binary hashes or pinned source build | Edge and Wasmer NAPI-V8 bridge |

`runtime.lock.json` is authoritative. Bundle versions are independent of Edge
and Wasmer versions and select one complete compatibility lock.

## Releases

Normal branch and pull-request runs retain Actions artifacts for CI inspection.
A Git tag matching `v$(cat VERSION)` runs every supported platform gate and,
only after all pass, creates a GitHub Release containing:

```text
wurster-edge-runtime-linux-amd64.tar.gz
wurster-edge-runtime-darwin-arm64.tar.gz
wurster-edge-runtime-darwin-amd64.tar.gz
wurster-edge-runtime-windows-amd64.zip
wurster-edge-runtime-core.tar.gz
SHA256SUMS
```

These GitHub Release assets are the final binaries for Wurster consumers. The
release job downloads the already-tested archives, recomputes one authoritative
checksum file, verifies it, and publishes all assets together. A partial
platform release cannot be created by the workflow.

Maintainer steps, version invariants, and recovery behavior are documented in
[docs/RELEASING.md](docs/RELEASING.md).
The machine-readable consumer fields are defined in
[docs/MANIFEST.md](docs/MANIFEST.md).

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

The portable archive instead has one top-level `wurster-edge-runtime-core/`
directory containing `wurster-edgejs.wasm`, `manifest.json`,
`runtime.lock.json`, and `LICENSES/`.

The WASIX guest is built once and reused byte-for-byte by all desktop hosts.
The core archive publishes those same bytes as `wurster-edgejs.wasm` with its
compatibility lock. Every platform manifest records the guest SHA-256, and the
release job compares all five final archives before publication. Native `edge`
and `wasmer` binaries are built and tested on their target operating system.

The host/guest boundary is intentionally independent of process spawning.
Desktop uses native executables today; future browser and embedded mobile hosts
remain Edge-runtime responsibilities. See [docs/HOST_CONTRACT.md](docs/HOST_CONTRACT.md).

## Build

CI is the supported reproducible build environment:

```bash
# Ubuntu 24.04 x86-64, with pinned wasixcc installed
./scripts/build-linux-amd64.sh

# macOS 15 Apple Silicon, using the guest produced above
./scripts/build-darwin-arm64.sh /path/to/edgejs.wasm

# macOS 15 Intel, building a pinned native x86_64 V8 host dependency
./scripts/build-darwin-amd64.sh /path/to/edgejs.wasm

# Windows Server 2025 x86-64, from PowerShell
./scripts/build-windows-amd64.ps1 -EdgeWasm C:\path\to\edgejs.wasm
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

GitHub Releases are public and are the only consumer distribution channel.
Wurster-Lab must pin an exact tag, download the matching target asset and
`SHA256SUMS` anonymously, verify the checksum, and only then stage/sign/package
the binaries. This repository deliberately does not apply Apple Developer ID
signing or notarization; that belongs to Wurster-Lab's final application build.
