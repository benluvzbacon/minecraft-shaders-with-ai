#!/usr/bin/env python3
"""Generate the thin program wrappers of the Horizon Shaders pack.

Iris treats a dimension folder (``world-1``, ``world1``) as a *complete* program
set: ``ShaderPack#getProgramSet`` says explicitly that "none of the files from
the parent directory are merged into the override". A program that is missing
from such a folder therefore falls back to Iris' own internal fallback shader,
not to the pack's Overworld version, so every dimension folder has to carry every
program the pack wants to run there.

Rather than copying 46 program files three times over, this script writes three
line wrappers that all include the same body from ``shaders/programs``:

    shaders/<name>.vsh            #version + stage define + include
    shaders/world-1/<name>.vsh    same, plus #define DIM_NETHER
    shaders/world1/<name>.vsh     same, plus #define DIM_END

The bodies never contain a ``#version`` directive. Iris' preprocessor hoists
every ``#version`` line it finds to the top of the file (see
``JcppProcessor``/``GlslCollectingListener``), so a second one coming in through
an include would end up as a duplicate directive and fail to compile.

Run it after adding or renaming a program:

    python3 tools/generate_programs.py
"""

from __future__ import annotations

import os
import sys

# Program name -> what it is used for. The list has to match the bodies in
# shaders/programs/; the generator fails if one of them is missing.
PROGRAMS = [
    "shadow",
    "gbuffers_basic",
    "gbuffers_textured",
    "gbuffers_textured_lit",
    "gbuffers_terrain",
    "gbuffers_block",
    "gbuffers_water",
    "gbuffers_entities",
    "gbuffers_lightning",
    "gbuffers_hand",
    "gbuffers_weather",
    "gbuffers_armor_glint",
    "gbuffers_spidereyes",
    "gbuffers_skybasic",
    "deferred",
    "composite",
    "composite1",
    "composite2",
    "composite3",
    "composite4",
    "composite5",
    "composite6",
    "final",
]

# Dimension folder -> (define written before the include, human readable name).
# The pack root is the Overworld and needs no define at all.
DIMENSIONS = [
    ("", None, "Overworld"),
    ("world-1", "DIM_NETHER", "Nether"),
    ("world1", "DIM_END", "End"),
]

STAGES = [
    ("vsh", "HZ_STAGE_VERTEX", "vertex"),
    ("fsh", "HZ_STAGE_FRAGMENT", "fragment"),
]

HEADER = """//==============================================================================
//
//   Horizon Shaders  -  {name} ({dimension}, {stage} stage)
//
//   GENERATED FILE, do not edit. tools/generate_programs.py writes this wrapper.
//   The program itself lives in shaders/programs/{name}.glsl and is shared by the
//   Overworld, the Nether (world-1) and the End (world1); lib/dimension.glsl
//   switches behaviour on the define below.
//
//   Iris does not merge a dimension folder with the pack root
//   (ShaderPack#getProgramSet), so each folder has to contain every program that
//   should be active in that dimension.
//
//==============================================================================
"""


def wrapper(program: str, extension: str, stage_define: str, stage_name: str,
            dimension: str, dimension_define: str | None) -> str:
    parts = [HEADER.format(name=program, dimension=dimension, stage=stage_name)]
    parts.append("#version 330 compatibility\n\n")

    if dimension_define is not None:
        parts.append("// Telling lib/dimension.glsl which dimension this is.\n")
        parts.append("#define %s\n" % dimension_define)

    parts.append("#define %s\n" % stage_define)
    parts.append('#include "/programs/%s.glsl"\n' % program)

    return "".join(parts)


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    shaders = os.path.join(root, "HorizonShaders", "shaders")
    bodies = os.path.join(shaders, "programs")

    missing = [p for p in PROGRAMS
               if not os.path.isfile(os.path.join(bodies, p + ".glsl"))]
    if missing:
        print("missing program bodies in shaders/programs: %s" % ", ".join(missing),
              file=sys.stderr)
        return 1

    written = 0

    for folder, dimension_define, dimension in DIMENSIONS:
        target = os.path.join(shaders, folder) if folder else shaders
        os.makedirs(target, exist_ok=True)

        for program in PROGRAMS:
            for extension, stage_define, stage_name in STAGES:
                path = os.path.join(target, "%s.%s" % (program, extension))
                text = wrapper(program, extension, stage_define, stage_name,
                               dimension, dimension_define)

                with open(path, "w", encoding="utf-8", newline="\n") as handle:
                    handle.write(text)

                written += 1

    print("wrote %d program wrappers for %d programs in %d locations"
          % (written, len(PROGRAMS), len(DIMENSIONS)))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
