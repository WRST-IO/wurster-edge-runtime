# Notices

This WRST.IO downstream bundle combines pinned upstream source trees with the
Wurster patch recorded in `manifest.json`:

- Edge.js and its bundled Node-compatible dependencies;
- Wasmer and its Rust dependencies;
- the shared Wasmer N-API implementation;
- the Edge.js WASIX guest built with wasixcc.

Upstream license and copying files discovered in the pinned source trees are
preserved below `LICENSES/edgejs/` and `LICENSES/wasmer/`. The generated
`LICENSES/wasmer-rust-dependencies.md` records Cargo package license expressions
and source/repository identifiers for the Wasmer build graph.

This notice is informational and does not replace the upstream license texts.
This bundle is not an official Wasmer or upstream Edge.js release.
