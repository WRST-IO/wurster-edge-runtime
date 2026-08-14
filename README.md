# Wurster Edge Runtime

Pinned, self-contained Edge.js/WASIX/Wasmer runtime for Wurster Pigsty.

The release artifact is intentionally an assembly of mutually tested upstream
revisions rather than a pair of unrelated nightly ZIP files. It contains a
native Linux `edge` launcher, a Wasmer CLI built with LLVM and the experimental
V8 N-API host bridge, and the matching engine-free Edge WASIX guest.

## Compatibility lock

| Component | Revision | Why this revision |
| --- | --- | --- |
| Edge.js | `1ca99ab4ff3d74bf5940177eb007457612d398e3` | Current upstream main used for the first Wurster bundle |
| Wasmer | `9b8fdf1720d6671a3de76aa8727f84536979104f` | Exact host revision used by Edge's successful Linux V8/WASIX CI lane |
| N-API | `c5b66fb9f5b1b997d5bdd463dc1a80bb174d4730` | Same submodule commit in both Edge and Wasmer |
| wasixcc | `v0.4.3`, sysroot `v2026-07-30.1` | Edge upstream WASIX build toolchain |

The upstream Edge run for this pair completed 1,676 selected Node
compatibility tests with zero failures, followed by its locale, framework, and
standalone V8/WASIX gates. This repository adds Pigsty-specific offline and
filesystem-boundary tests on the assembled artifact.

## Bundle layout

```text
wurster-edge-runtime-linux-amd64/
  bin/edge
  bin/wasmer
  share/edge-wasix/
    edgejs.wasm
    wasmer.toml
  manifest.json
  LICENSES/
  README.md
```

## Build

The supported build host is Ubuntu 24.04 on amd64. CI installs the pinned
wasixcc action and then runs:

```bash
./scripts/build-linux-amd64.sh
./scripts/verify-bundle.sh out/wurster-edge-runtime-linux-amd64
```

The equivalent convenience targets are `make check`, `make fetch`, `make
build`, and `make verify`.

Build products are written under `out/`; source checkouts and compiler outputs
stay under `build/`. The build requires network access. The resulting bundle
does not.

## Wurster integration

Set absolute paths when launching Pigsty:

```bash
export WURSTER_EDGE_BIN=/opt/wurster-edge-runtime/bin/edge
export WASMER_BIN=/opt/wurster-edge-runtime/bin/wasmer
export EDGE_WASMER_PACKAGE=/opt/wurster-edge-runtime/share/edge-wasix
cd /path/to/projected/wurst
exec "$WURSTER_EDGE_BIN" --safe tool.js
```

`--safe` mounts only the current working directory through Wasmer. The Wurster
integration must therefore enter the projected `/wurst` workspace before
launching Edge. A future explicit mount launcher can add read-only
`/toolchain` and writable `/tmp`; those projections remain Wurster's job.

The Wurster patch removes Edge upstream's unconditional `--net` grant. Pigsty
starts without a network capability and does not inherit the host's `HOME`;
the guest receives `HOME=/tmp`. There is no system-Node or host-shell fallback.

## Verification

`scripts/verify-bundle.sh` checks:

- the required Wasmer N-API feature markers;
- local-only package references and all manifest hashes;
- `process.version` through `edge --safe`;
- synchronous `node:fs` directory, write, and read operations;
- denial of a sentinel file outside the mounted working directory;
- absence of host `node` and shell fallbacks, including an `execve` trace;
- the exact safe-mode command contract, including absence of `--net`.

CI is configured to repeat the runtime suite inside a Linux network namespace
with no network interface route. See [SECURITY.md](SECURITY.md) for the boundary
and known limitations, and [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md) for the
executable acceptance matrix.

## Versioning

Bundle versions are independent of Edge and Wasmer versions. A version selects
one complete compatibility lock. Changing any pinned commit, toolchain, patch,
or package manifest requires a new bundle version and a full Linux smoke run.
