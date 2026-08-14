# Fork provenance and policy

Wurster Edge Runtime is a WRST.IO-maintained downstream fork distribution of
Edge.js. The repository intentionally stores the compatibility lock, patches,
build system, tests, and packaging rather than copying entire upstream source
trees. Builds fetch the exact commits recorded in `runtime.lock.json` and apply
the reviewable patches under `patches/`.

## Upstreams

- Edge.js: <https://github.com/wasmerio/edgejs>
- Wasmer: <https://github.com/wasmerio/wasmer>
- shared N-API bridge: <https://github.com/wasmerio/napi>
- wasixcc: <https://github.com/wasix-org/wasixcc>

The Edge.js and Wasmer names remain those of their respective upstream
projects. WRST.IO does not claim this bundle is endorsed by, or is an official
release of, those projects.

## Downstream delta

The Wurster patch currently changes the Edge safe-mode launcher contract to:

- select the LLVM Wasmer backend expected by the tested NAPI pairing;
- omit the upstream unconditional `--net` capability;
- expose guest `HOME=/tmp` rather than inheriting host `HOME`.

The Windows downstream delta additionally supplies native safe-mode process
spawning, enables Wasmer's NAPI-V8 host on Windows, adds the published Windows
V8 library layout to both NAPI resolvers, and selects Wasmer's Windows V8 WASM
backend rather than LLVM.

Windows also selects OpenSSL's vendored `no-asm` source set because upstream's
NASM-formatted VC-WIN64A files are otherwise sent to MSVC's incompatible MASM
assembler. The Darwin Intel host is built natively. Its V8 dependency is
compiled from the pinned V8 revision with the pinned upstream custom-build
patchset because no Darwin x86_64 binary exists in the V8 11.9.7 release.

The local WASIX package manifest removes upstream references to absent
`quickjs-wasm/etc` and `quickjs-wasm/pnpm` paths and contains no registry or CDN
dependency. WurstFS projection is deliberately not implemented in this fork.

## Update policy

An upstream update is one atomic compatibility-lock change. Edge.js, Wasmer,
N-API, compiler/sysroot, LLVM assets, patches, and package manifest are reviewed
as a unit. The bundle version must change, and every supported target must pass
its full acceptance suite before a tag can publish a release.

Upstream fixes should be preferred where they satisfy Pigsty's security model.
Wurster-only changes remain small, explicit patches suitable for rebasing or
submission upstream.
