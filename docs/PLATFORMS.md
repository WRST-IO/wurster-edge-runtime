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

## macOS Intel

Built natively on GitHub's `macos-15-intel` x86_64 runner. This is a real Intel
build: both binaries must be Mach-O x86_64. It uses the same guest as every
other host. Because the upstream custom-build release does not publish a Darwin
x86_64 asset, CI builds its pinned V8 commit with the pinned `v8-custom-builds`
patchset and pinned depot_tools revision; no ARM bundle or Rosetta compatibility
substitution is accepted.

## Windows amd64

Windows is a mandatory release target. The pinned upstream sources contain most
of the necessary pieces but do not connect them into a working safe runtime:

- Edge has Windows process spawning for compatibility commands, while its
  safe-mode capture and passthrough functions still use POSIX-only
  `pipe/fork/execvp/waitpid`;
- Wasmer's Makefile explicitly removes `napi-v8` on Windows;
- the shared NAPI resolver recognizes `windows-amd64`, but the archive published
  under the upstream release label `11.9.7` is incomplete on Windows. Its
  internal version is V8 `13.6.233.17`, and it omits required public cppgc
  headers. WRST.IO therefore builds the Windows library and complete header
  tree from the matching pinned V8 source commit instead of consuming that
  archive.

The WRST.IO patches complete these paths. Windows uses Wasmer's supported V8
WASM backend (`--v8`) instead of unavailable LLVM, while retaining the same
NAPI import ABI and the byte-identical Edge WASIX guest used on Linux and macOS.
The bundle is built natively on GitHub's Windows Server 2025 amd64 runner.

Relevant upstream evidence:

- [Wasmer pinned Makefile](https://github.com/wasmerio/wasmer/blob/9b8fdf1720d6671a3de76aa8727f84536979104f/Makefile)
- [shared NAPI Windows target matcher](https://github.com/wasmerio/napi/blob/c5b66fb9f5b1b997d5bdd463dc1a80bb174d4730/build.rs)
- [V8 custom-build asset release 11.9.7](https://github.com/wasmerio/v8-custom-builds/releases/tag/11.9.7),
  whose verified internal engine version is `13.6.233.17`

A Windows asset is released only when all of the following are true:

1. a Windows NAPI-V8 Wasmer host can be built from pinned sources;
2. Edge and Wasmer use the identical pinned N-API revision;
3. `edge --safe`, `node:fs`, write persistence, and filesystem escape denial
   pass on Windows;
4. offline start and absence of host Node/PowerShell/cmd fallback are proven;
5. the final Windows bundle is produced and published by the same tag-gated
   release job.

The CI gate verifies PE32+ amd64 binaries, blocks outbound traffic for both
executables with Windows Firewall, poisons `PATH` with Node/cmd/PowerShell
probes, and exercises parent plus directory-junction escape attempts. A failed
Windows job prevents the entire tagged release; Linux/macOS-only output is not
considered a final Wurster Edge Runtime release.

## Portable core, Web, and mobile

`wurster-edge-runtime-core.tar.gz` is supported and contains the tested
platform-neutral guest as `wurster-edgejs.wasm`, its manifest, compatibility
lock, and licenses. It is not a host by itself.

`web`, `ios-arm64`, and `android-arm64` are reserved host identifiers, not
supported targets in this release. Web still lacks a packaged and gated browser
WASIX/N-API/Worker host. Mobile packaging remains deliberately unspecified.
All Edge-specific work for those hosts belongs in this repository under the
logical contract in [HOST_CONTRACT.md](HOST_CONTRACT.md), so Wurster-Lab never
needs to implement Edge or N-API internals.
