# Acceptance matrix

The release job may publish only after the native verification suite passes on
Linux amd64, macOS arm64, native macOS amd64, and Windows amd64. Linux repeats
inside `unshare --net`; Windows repeats with outbound firewall rules for both
bundled executables. The checks map to the Pigsty runtime requirements as
follows.

| Requirement | Executable gate |
| --- | --- |
| `edge --safe` starts | `process.version` smoke through bundled Edge, Wasmer, and local WASIX package |
| `node:fs` works | creates `dist/out.txt`, writes `pigsty-ok`, reads it back |
| writes persist in workspace | host verifies the projected `dist/out.txt` contents |
| outside access blocked | `../host-secret` plus a symlink (Unix) or directory junction (Windows) escape must fail |
| offline start | Linux uses a network namespace; Windows Firewall blocks both executables; every platform proves the safe command has no `--net` or remote package reference |
| no host Node/shell fallback | all platforms poison `PATH`; Windows probes Node, cmd, Windows PowerShell, and pwsh; Linux additionally audits every `execve` with `strace` |
| local package override | intercepted Wasmer argv must contain the exact `EDGE_WASMER_PACKAGE` path |
| local Wasmer override | all runtime calls set the exact bundle `WASMER_BIN` path |
| no broken mounts | package manifest has no `[fs]`, `quickjs-wasm/etc`, or `quickjs-wasm/pnpm` |
| matching N-API ABI | source fetch asserts both gitlinks equal `c5b66fb`; Wasmer feature markers and Edge WASM import validator must pass; safe mode uses a pinned platform-supported backend |
| versioned and traceable | lock file, generated manifest, per-file hashes, deterministic tar/ZIP metadata, archive checksum, and guest SHA-256 |
| path-only Wurster integration | acceptance commands set only binary/package paths and start from the projected workspace |

Every runtime suite is repeated against a fresh extraction of the final archive,
not only its staging directory. The central release job also opens all five
archives, verifies every manifest, compares every compatibility lock, and
requires byte-identical guest contents. It cannot run until all four desktop
jobs have uploaded their verified final archives and the core archive exists.
See [PLATFORMS.md](PLATFORMS.md).
