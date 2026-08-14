#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", required=True, type=Path)
    parser.add_argument("--lock", required=True, type=Path)
    parser.add_argument("--patch-root", required=True, type=Path)
    parser.add_argument("--target", required=True)
    args = parser.parse_args()

    bundle = args.bundle.resolve()
    lock = json.loads(args.lock.read_text(encoding="utf-8"))

    files = []
    for path in sorted(bundle.rglob("*")):
        if not path.is_file() or path.name == "manifest.json":
            continue
        files.append(
            {
                "path": path.relative_to(bundle).as_posix(),
                "sha256": sha256(path),
                "size": path.stat().st_size,
                "executable": bool(path.stat().st_mode & 0o111),
            }
        )

    patches = []
    for path in sorted(args.patch_root.rglob("*.patch")):
        patches.append(
            {
                "path": path.relative_to(args.patch_root.parent).as_posix(),
                "sha256": sha256(path),
            }
        )

    executable_suffix = ".exe" if args.target == "windows-amd64" else ""
    manifest = {
        "schema": 1,
        "name": lock["bundle"]["name"],
        "version": lock["bundle"]["version"],
        "target": args.target,
        "sources": lock["sources"],
        "toolchain": lock["toolchain"],
        "patches": patches,
        "runtime_contract": {
            "edge": f"bin/edge{executable_suffix}",
            "wasmer": f"bin/wasmer{executable_suffix}",
            "edge_wasmer_package": "share/edge-wasix",
            "network_default": "disabled",
            "guest_home": "/tmp",
            "host_node_fallback": False,
        },
        "files": files,
    }
    output = bundle / "manifest.json"
    output.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(output, 0o644)


if __name__ == "__main__":
    main()
