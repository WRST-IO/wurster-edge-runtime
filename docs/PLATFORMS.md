# Platform support

## Linux amd64

Built natively on GitHub's Ubuntu 24.04 x64 runner. This is the primary Pigsty
target and receives both the normal acceptance run and a second complete run
inside a network namespace without a route. The `execve` audit proves that safe
mode starts bundled Wasmer and no host Node or shell process.

## macOS Apple Silicon

Built natively on GitHub's `macos-15` arm64 runner. It uses the same tested
`edgejs.wasm` as Linux and target-native Edge and Wasmer binaries. The complete
runtime, filesystem, manifest, PATH-poison, and safe-command tests run on macOS.
Linux-only `strace` and network-namespace gates are not claimed on Darwin.

macOS Intel is intentionally outside the Wurster release matrix.

## Windows amd64

Windows is a required future Wurster platform, but it is not releasable with the
current pinned upstream pair. Wasmer's pinned Makefile adds `napi-v8` only when
`IS_WINDOWS` is not set, and the matching `wasmer-v8` custom-build release has
Linux and Darwin archives but no Windows archive. A normal Wasmer executable is
therefore insufficient: Edge safe mode needs the matching NAPI extension host
imports.

Relevant upstream evidence:

- [Wasmer pinned Makefile](https://github.com/wasmerio/wasmer/blob/9b8fdf1720d6671a3de76aa8727f84536979104f/Makefile)
- [Wasmer V8 custom builds 11.9.2](https://github.com/wasmerio/wasmer-v8-custom-builds/releases/tag/11.9.2)

A Windows asset may be added only when all of the following are true:

1. a Windows NAPI-V8 Wasmer host can be built from pinned sources;
2. Edge and Wasmer use the identical pinned N-API revision;
3. `edge --safe`, `node:fs`, write persistence, and filesystem escape denial
   pass on Windows;
4. offline start and absence of host Node/PowerShell/cmd fallback are proven;
5. the final Windows bundle is produced and published by the same tag-gated
   release job.

Until then, the workflow deliberately publishes no Windows `.exe` or archive.
This is a compatibility boundary, not an Actions-runner limitation.
