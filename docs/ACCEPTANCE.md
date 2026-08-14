# Acceptance matrix

The release job may publish only after `scripts/verify-bundle.sh` passes on
Linux amd64 and macOS arm64. Linux repeats the suite inside `unshare --net`.
The checks map to the Pigsty runtime requirements as follows.

| Requirement | Executable gate |
| --- | --- |
| `edge --safe` starts | `process.version` smoke through bundled Edge, Wasmer, and local WASIX package |
| `node:fs` works | creates `dist/out.txt`, writes `pigsty-ok`, reads it back |
| writes persist in workspace | host verifies the projected `dist/out.txt` contents |
| outside access blocked | both `../host-secret` and a symlink to that sentinel must fail |
| offline start | Linux repeats the full suite in a network namespace without a route; both platforms prove the safe command has no `--net` or remote package reference |
| no host Node/shell fallback | both platforms poison `PATH`; Linux additionally audits every `execve` with `strace` |
| local package override | intercepted Wasmer argv must contain the exact `EDGE_WASMER_PACKAGE` path |
| local Wasmer override | all runtime calls set the exact bundle `WASMER_BIN` path |
| no broken mounts | package manifest has no `[fs]`, `quickjs-wasm/etc`, or `quickjs-wasm/pnpm` |
| matching N-API ABI | source fetch asserts both gitlinks equal `c5b66fb`; Wasmer feature markers and Edge WASM import validator must pass; safe mode uses the same LLVM backend as upstream CI |
| versioned and traceable | lock file, generated manifest, per-file hashes, deterministic tar metadata, and archive checksum |
| path-only Wurster integration | acceptance commands set only binary/package paths and start from the projected workspace |

The generated artifacts themselves are the evidence. The central release job
cannot run until both target jobs have uploaded their verified final archives.
Windows remains unreleased until it can pass equivalent native gates; see
[PLATFORMS.md](PLATFORMS.md).
