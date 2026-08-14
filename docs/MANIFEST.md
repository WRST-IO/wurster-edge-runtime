# Manifest contract

Every release bundle contains a generated `manifest.json`. Schema `1` is the
public machine-readable consumer contract for Wurster-Lab.

- `schema`: integer manifest schema, currently `1`.
- `name`: always `wurster-edge-runtime`.
- `version`: exactly `VERSION`, without a leading `v`.
- `target`: `core` or an exact supported target ID.
- `files`: complete sorted list of bundle files except `manifest.json`, each
  with `path`, `sha256`, `size`, and `executable`.
- `sources`: every compatibility-locked upstream repository and commit.
- `toolchain`: build hosts, compiler/runtime versions, source epoch, verified
  dependency archives, wasixcc/sysroot, and Wasmer features.
- `patches`: every WRST.IO patch path and SHA-256.
- `wasix_guest`: path and SHA-256 of the guest in this bundle.
- `runtime_contract`: host form and security/runtime defaults.

Desktop `runtime_contract.host_kind` is `native-process`; its object also names
the bundled Edge and Wasmer binaries and local WASIX package directory. Core is
`portable-wasix-guest` and names `wurster-edgejs.wasm` directly. This
distinction prevents native process execution from becoming the universal host
API.

Consumers must first verify the archive digest from the release's
`SHA256SUMS`, then verify the manifest file set and hashes. A desktop bundle is
compatible with a core bundle only when their `version`, compatibility lock,
and `wasix_guest.sha256` match. The release workflow additionally proves byte
identity, not only equal metadata.
