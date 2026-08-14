#!/usr/bin/env python3

import argparse
import hashlib
import json
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("bundle", type=Path)
    args = parser.parse_args()
    bundle = args.bundle.resolve()
    manifest = json.loads((bundle / "manifest.json").read_text(encoding="utf-8"))

    expected = {entry["path"]: entry for entry in manifest["files"]}
    actual = {
        path.relative_to(bundle).as_posix(): path
        for path in bundle.rglob("*")
        if path.is_file() and path.name != "manifest.json"
    }
    if set(expected) != set(actual):
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        raise SystemExit(f"manifest file set mismatch; missing={missing}, extra={extra}")

    for relative, entry in expected.items():
        path = actual[relative]
        if path.stat().st_size != entry["size"]:
            raise SystemExit(f"size mismatch: {relative}")
        if sha256(path) != entry["sha256"]:
            raise SystemExit(f"sha256 mismatch: {relative}")

    guest = manifest.get("wasix_guest", {})
    guest_path = guest.get("path")
    if guest_path not in expected:
        raise SystemExit("manifest WASIX guest is not in the file contract")
    if guest.get("sha256") != expected[guest_path]["sha256"]:
        raise SystemExit("manifest WASIX guest hash disagrees with file contract")

    print(f"manifest verified: {len(actual)} files")


if __name__ == "__main__":
    main()
