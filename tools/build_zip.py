#!/usr/bin/env python3
"""Package the Horizon Shaders pack into a zip that drops into shaderpacks.

Iris reads a shader pack from a directory or a zip whose *root* is the `shaders`
folder, so the archive has to look like this once extracted into
`.minecraft/shaderpacks`:

    .minecraft/shaderpacks/HorizonShaders.zip
        shaders/
            shaders.properties
            block.properties
            lang/en_us.lang
            programs/...
            lib/...
            gbuffers_terrain.vsh / .fsh
            world-1/...   (Nether)
            world1/...    (End)

Nothing else belongs at the root of the archive: a wrapper directory such as
`HorizonShaders/shaders/` would make Iris look for
`HorizonShaders/shaders/shaders.properties` and fail to load the pack.

Usage:
    python3 tools/build_zip.py                       -> dist/HorizonShaders.zip
    python3 tools/build_zip.py --version 1.0.0       -> dist/HorizonShaders-1.0.0.zip
    python3 tools/build_zip.py --output /tmp/pack.zip
"""

from __future__ import annotations

import argparse
import os
import sys
import zipfile
from pathlib import Path
from typing import List

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent
PACK_ROOT = REPO_ROOT / "HorizonShaders"
SHADERS_ROOT = PACK_ROOT / "shaders"
DEFAULT_OUTPUT = REPO_ROOT / "dist" / "HorizonShaders.zip"

# Directory names and file patterns that must never end up in a shipped pack.
EXCLUDED_NAMES = {".DS_Store", "Thumbs.db", "desktop.ini", "__pycache__"}
EXCLUDED_SUFFIXES = (".pyc", ".bak", ".swp", ".orig", ".tmp")

# A fixed timestamp keeps the archive byte for byte reproducible, which makes it
# easy to tell whether two builds of the same sources actually differ.
FIXED_DATE = (1980, 1, 1, 0, 0, 0)


def collect_files() -> List[Path]:
    """Every file of the pack, in a stable order."""

    if not SHADERS_ROOT.is_dir():
        raise SystemExit("missing pack directory: %s" % SHADERS_ROOT)

    files = []

    for path in sorted(SHADERS_ROOT.rglob("*")):
        if not path.is_file():
            continue

        if any(part in EXCLUDED_NAMES for part in path.parts):
            continue

        if path.name.endswith(EXCLUDED_SUFFIXES):
            continue

        files.append(path)

    return files


def build_zip(files: List[Path], output: Path) -> None:
    """Write the archive with `shaders/` as its only top level entry."""

    output.parent.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            relative = path.relative_to(SHADERS_ROOT).as_posix()
            info = zipfile.ZipInfo("shaders/" + relative, date_time=FIXED_DATE)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16

            archive.writestr(info, path.read_bytes())

        # Directories are implied by the entry names, but an explicit entry for
        # every folder keeps some unzip implementations happy.
        directories = sorted({
            os.path.dirname("shaders/" + path.relative_to(SHADERS_ROOT).as_posix())
            for path in files
        } - {""})

        for directory in directories:
            if directory == "shaders":
                continue

            info = zipfile.ZipInfo(directory + "/", date_time=FIXED_DATE)
            info.external_attr = 0o755 << 16 | 0x10

            archive.writestr(info, b"")


def verify_zip(output: Path) -> None:
    """Fail loudly if the archive would not load in Iris."""

    required = [
        "shaders/shaders.properties",
        "shaders/block.properties",
        "shaders/lang/en_us.lang",
    ]

    with zipfile.ZipFile(output) as archive:
        names = set(archive.namelist())

        roots = {name.split("/")[0] for name in names if name}

        if roots != {"shaders"}:
            raise SystemExit(
                "%s does not have `shaders` as its only top level entry, found %s"
                % (output, sorted(roots))
            )

        missing = [entry for entry in required if entry not in names]

        if missing:
            raise SystemExit("%s is missing %s" % (output, ", ".join(missing)))


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT),
                        help="where to write the archive (default: %(default)s)")
    parser.add_argument("--version", default=None,
                        help="append a version to the default file name, e.g. "
                             "HorizonShaders-1.0.0.zip (ignored when --output is given)")
    arguments = parser.parse_args(argv)

    output = Path(arguments.output)

    if arguments.version and output == DEFAULT_OUTPUT:
        output = output.with_name("HorizonShaders-%s.zip" % arguments.version)

    files = collect_files()

    if not files:
        raise SystemExit("no files found under %s" % SHADERS_ROOT)

    build_zip(files, output)
    verify_zip(output)

    size = output.stat().st_size

    print("wrote %s" % output)
    print("  %d files, %.1f KiB" % (len(files), size / 1024.0))
    print("  extract into .minecraft/shaderpacks, the archive already contains "
          "shaders/ at its root")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
