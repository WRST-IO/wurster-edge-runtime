#!/usr/bin/env python3

import argparse
import datetime
import os
import zipfile
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--epoch", required=True, type=int)
    args = parser.parse_args()

    directory = args.directory.resolve()
    timestamp = datetime.datetime.fromtimestamp(args.epoch, datetime.UTC)
    date_time = (
        timestamp.year,
        timestamp.month,
        timestamp.day,
        timestamp.hour,
        timestamp.minute,
        timestamp.second,
    )

    with zipfile.ZipFile(
        args.output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
    ) as archive:
        for path in sorted(directory.rglob("*")):
            if not path.is_file():
                continue
            relative = Path(directory.name) / path.relative_to(directory)
            info = zipfile.ZipInfo(relative.as_posix(), date_time=date_time)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            mode = 0o755 if path.suffix.lower() == ".exe" else 0o644
            info.external_attr = (mode & 0xFFFF) << 16
            info.flag_bits |= 0x800
            archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED)


if __name__ == "__main__":
    main()
