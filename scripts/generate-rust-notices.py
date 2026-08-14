#!/usr/bin/env python3

import argparse
import json
import subprocess
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest-path", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    completed = subprocess.run(
        [
            "cargo",
            "metadata",
            "--locked",
            "--format-version",
            "1",
            "--manifest-path",
            str(args.manifest_path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    metadata = json.loads(completed.stdout)
    packages = sorted(
        metadata["packages"],
        key=lambda package: (package["name"].casefold(), package["version"], package["id"]),
    )

    lines = [
        "# Wasmer Rust dependency notices",
        "",
        "Generated from the locked Cargo metadata used to build bundled Wasmer.",
        "License values are SPDX expressions supplied by each package.",
        "",
        "| Package | Version | License | Source / repository |",
        "| --- | --- | --- | --- |",
    ]
    for package in packages:
        source = package.get("source") or package.get("repository") or "workspace"
        values = [
            package["name"],
            package["version"],
            package.get("license") or "not declared",
            source,
        ]
        escaped = [str(value).replace("|", "\\|").replace("\n", " ") for value in values]
        lines.append("| " + " | ".join(escaped) + " |")

    args.output.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
