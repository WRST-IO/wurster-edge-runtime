# Wurster Edge Runtime — Linux amd64

This directory is a complete Pigsty engine bundle. It is expected to run
offline and must be kept intact: `bin/edge`, `bin/wasmer`, and
`share/edge-wasix` are one tested compatibility unit.

From the projected Wurst workspace:

```bash
export WURSTER_EDGE_BIN=/absolute/path/to/bin/edge
export WASMER_BIN=/absolute/path/to/bin/wasmer
export EDGE_WASMER_PACKAGE=/absolute/path/to/share/edge-wasix
exec "$WURSTER_EDGE_BIN" --safe app.js
```

Safe mode mounts only the current directory, supplies guest `HOME=/tmp`, and
does not grant networking. It neither calls a host Node binary nor falls back
to a host shell. The package manifest contains no registry dependency and no
implicit filesystem mounts.

`manifest.json` records every source revision, build feature, Wurster patch,
and file checksum. Verify it with the repository's
`scripts/verify-manifest.py` before installation.
