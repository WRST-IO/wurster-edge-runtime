# Edge Pigsty host contract

`wurster-edge-runtime` owns the portable Edge.js WASIX guest and every host
that supplies its WASIX, N-API, and Edge extension imports. Wurster-Lab owns
PigFS projection, capabilities, lifecycle policy, resource policy, and Pigsty
orchestration. Neither PigFS nor `.wurst` semantics belong in this repository;
Edge-, Wasmer-, WASIX-, or N-API-specific host glue does not belong in
Wurster-Lab.

The stable architectural boundary is host/guest, not process/child-process:

```text
Wurster-Lab Pigsty orchestration
             |
      Edge Pigsty host
             |
      wurster-edgejs.wasm
```

A host implementation must logically provide these operations, whether it is
a native process pair, browser Worker, embedded library, framework, or another
container:

- initialize and report its runtime version and capabilities;
- load the exact compatibility-locked `wurster-edgejs.wasm` guest;
- provide or mount the virtual workspace and set its working directory;
- provide explicit argv and environment values;
- start a JavaScript/Node-compatible entry point;
- expose stdin, stdout, stderr, completion, and exit code;
- terminate execution;
- apply the network policy supplied by Wurster;
- apply resource limits supported by that host and report unsupported limits.

The security invariants are part of this logical contract: no host Node or
shell fallback, no ambient host filesystem or process access, no implicit host
environment, guest `HOME=/tmp`, and only explicit mounts/capabilities. A host
must fail closed when it cannot honor the requested policy.

The current desktop implementation realizes this contract with native `edge`
and `wasmer` executables. `spawn(edge)` is a desktop adapter detail, not a
portable API requirement. A future browser host may use JavaScript, WebAssembly,
and Workers; mobile hosts may embed libraries. Packaging formats for iOS and
Android are intentionally not fixed yet.

## Reserved future hosts

- `web` / `wurster-edge-runtime-web.tar.gz`
- `ios-arm64`
- `android-arm64`

These identifiers are reservations, not support claims. A target becomes
supported only after a reproducible host bundle passes its own filesystem,
capability, lifecycle, offline, and fallback-denial gates.

The pinned Edge source exposes an engine-free WASIX guest and upstream browser
regression evidence, but it does not currently provide a standalone,
compatibility-locked browser host bundle containing the complete WASIX,
N-API/Edge-extension import implementation, Worker lifecycle adapter, PigFS
mount adapter, policy enforcement, and release tests. Therefore this release
publishes the portable core but does not publish or claim support for `web`.
That missing browser host belongs here when implemented; Wurster-Lab will only
consume it through this logical contract.
