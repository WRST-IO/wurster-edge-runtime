#!/usr/bin/env python3

import hashlib
import json
import sys
import tarfile
import zipfile
from pathlib import Path, PurePosixPath


TARGETS = ("linux-amd64", "darwin-arm64", "darwin-amd64", "windows-amd64")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def relative_member(name: str, expected_root: str) -> str | None:
    path = PurePosixPath(name.replace("\\", "/"))
    if path.is_absolute() or ".." in path.parts or not path.parts:
        raise SystemExit(f"unsafe archive member: {name}")
    if path.parts[0] != expected_root:
        raise SystemExit(f"unexpected archive top-level entry: {name}")
    if len(path.parts) == 1:
        return None
    return PurePosixPath(*path.parts[1:]).as_posix()


def read_tar(path: Path, expected_root: str) -> dict[str, bytes]:
    files = {}
    with tarfile.open(path, "r:gz") as archive:
        for member in archive.getmembers():
            relative = relative_member(member.name, expected_root)
            if member.isdir():
                continue
            if not member.isfile() or relative is None:
                raise SystemExit(f"unsupported tar member: {member.name}")
            stream = archive.extractfile(member)
            assert stream is not None
            files[relative] = stream.read()
    return files


def read_zip(path: Path, expected_root: str) -> dict[str, bytes]:
    files = {}
    with zipfile.ZipFile(path) as archive:
        for member in archive.infolist():
            relative = relative_member(member.filename, expected_root)
            if member.is_dir():
                continue
            if relative is None:
                raise SystemExit(f"unsupported zip member: {member.filename}")
            files[relative] = archive.read(member)
    return files


def verify_manifest(files: dict[str, bytes], target: str) -> dict:
    try:
        manifest = json.loads(files["manifest.json"])
    except KeyError as error:
        raise SystemExit(f"{target}: manifest.json is missing") from error
    if manifest["schema"] != 1 or manifest["name"] != "wurster-edge-runtime":
        raise SystemExit(f"{target}: invalid manifest identity")
    if manifest["target"] != target:
        raise SystemExit(f"{target}: manifest target mismatch")

    expected = {entry["path"]: entry for entry in manifest["files"]}
    actual = {name: data for name, data in files.items() if name != "manifest.json"}
    if set(expected) != set(actual):
        raise SystemExit(f"{target}: manifest file set mismatch")
    for name, entry in expected.items():
        data = actual[name]
        if len(data) != entry["size"] or sha256(data) != entry["sha256"]:
            raise SystemExit(f"{target}: manifest mismatch for {name}")

    guest = manifest["wasix_guest"]
    if guest["path"] not in actual or sha256(actual[guest["path"]]) != guest["sha256"]:
        raise SystemExit(f"{target}: WASIX guest contract mismatch")
    return manifest


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: verify-release-set.py RELEASE_ASSET_DIRECTORY")
    asset_dir = Path(sys.argv[1])
    archives = {
        "core": asset_dir / "wurster-edge-runtime-core.tar.gz",
        "linux-amd64": asset_dir / "wurster-edge-runtime-linux-amd64.tar.gz",
        "darwin-arm64": asset_dir / "wurster-edge-runtime-darwin-arm64.tar.gz",
        "darwin-amd64": asset_dir / "wurster-edge-runtime-darwin-amd64.tar.gz",
        "windows-amd64": asset_dir / "wurster-edge-runtime-windows-amd64.zip",
    }
    missing = [path.name for path in archives.values() if not path.is_file()]
    if missing:
        raise SystemExit(f"release assets missing: {missing}")

    bundles = {}
    manifests = {}
    for target, archive in archives.items():
        root = f"wurster-edge-runtime-{target}"
        files = read_zip(archive, root) if archive.suffix == ".zip" else read_tar(archive, root)
        bundles[target] = files
        manifests[target] = verify_manifest(files, target)

    core_guest = bundles["core"]["wurster-edgejs.wasm"]
    core_hash = sha256(core_guest)
    lock_bytes = bundles["core"]["runtime.lock.json"]
    for target in TARGETS:
        guest_path = "share/edge-wasix/edgejs.wasm"
        if bundles[target][guest_path] != core_guest:
            raise SystemExit(f"{target}: guest bytes differ from core")
        if manifests[target]["wasix_guest"]["sha256"] != core_hash:
            raise SystemExit(f"{target}: guest hash differs from core")
        if bundles[target]["runtime.lock.json"] != lock_bytes:
            raise SystemExit(f"{target}: compatibility lock differs from core")

    print(f"release set verified; shared WASIX guest sha256={core_hash}")


if __name__ == "__main__":
    main()
