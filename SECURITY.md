# Pigsty runtime security boundary

The security boundary is Wasmer/WASIX, not the native Edge launcher. The
launcher validates the bundled Wasmer feature set and starts the engine-free
Edge WASIX guest through `wasmer run --experimental-napi`.

Default capabilities:

- filesystem: only the launcher's current directory (`--volume=.`);
- working data: relative reads and writes inside that mounted directory;
- home: guest-only `HOME=/tmp`; the host `HOME` is not forwarded;
- network: disabled because the Wurster patch does not pass `--net`;
- environment: Wasmer does not forward the host environment wholesale;
- process execution: WASIX guest semantics only; no shell or system Node
  fallback is implemented by the launcher.

The local package manifest contains no filesystem mounts. In particular it has
no references to the upstream nightly's absent `quickjs-wasm/etc` or
`quickjs-wasm/pnpm` directories.

## Integration obligations

Wurster must make the projected Wurst workspace the process working directory
before invoking `bin/edge --safe`. Do not launch from a directory containing
host secrets. Future `/toolchain` and `/tmp` mounts should be explicit,
canonicalized, and created by Wurster; Edge does not understand WurstFS.

The N-API bridge is experimental upstream and has not been independently
audited by this project. Treat a change to Edge, Wasmer, N-API, wasixcc, the
sysroot, or the Wurster patch as an ABI/security change requiring a new bundle
and complete verification.

These invariants apply to every future host, including browser Workers and
embedded mobile libraries. Native process spawning is not the boundary and is
not required by the platform-neutral host contract. Hosts must fail closed when
they cannot enforce Wurster's mounts, network policy, or requested resource
limits. See [docs/HOST_CONTRACT.md](docs/HOST_CONTRACT.md).
