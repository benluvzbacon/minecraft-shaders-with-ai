#!/usr/bin/env python3
"""Validate the Horizon Shaders pack the way Iris loads it.

The pack is validated offline, without Minecraft, by re-implementing the parts of
Iris that decide whether a pack loads and by compiling every program with
glslang. Each check names the Iris class whose behaviour it mirrors:

  include expansion        IncludeProcessor / IncludeGraph / FileNode
  #version hoisting        GlslCollectingListener + JcppProcessor
  option discovery         OptionAnnotatedSource (parseLine / parseDefineOption /
                           parseIfdef) and ShaderPackOptions (boolean defines are
                           only registered when some source references them with
                           #ifdef or #ifndef)
  option value editing     OptionAnnotatedSource#edit through LineTransform
  comment directives       CommentDirectiveParser (DRAWBUFFERS / RENDERTARGETS,
                           read from fragment sources only)
  const directives         ConstDirectiveParser (fragment sources only)
  properties               ShaderProperties + PropertiesPreprocessor + ProfileSet
                           + BooleanParser
  language files           LanguageMap and the widget classes that look keys up
  program layout           ProgramSet / ShaderPack#getProgramSet

glslang is run in link mode (-l) on every vertex/fragment pair, which compiles
both stages and validates the interface between them. Iris rewrites the source
before handing it to the driver (attribute/varying, gl_FragColor, texture2D, ...
see CommonTransformer), and that rewrite is deliberately *not* simulated here:
the pack is written in the "compatibility" dialect that Iris accepts as input, so
validating exactly that input is what matters. The rewrite is mechanical and is
checked separately by the linting rules below.

Usage:
    python3 tools/validate.py                 # everything except the zip
    python3 tools/validate.py --zip dist/HorizonShaders.zip
    python3 tools/validate.py --keep-expanded /tmp/expanded
    python3 tools/validate.py --glslang /usr/bin/glslangValidator
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import tempfile
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from generate_programs import DIMENSIONS, PROGRAMS, STAGES, wrapper as build_wrapper  # noqa: E402

REPO_ROOT = HERE.parent
PACK_ROOT = REPO_ROOT / "HorizonShaders"
SHADERS_ROOT = PACK_ROOT / "shaders"
BODY_ROOT = SHADERS_ROOT / "programs"
LIB_ROOT = SHADERS_ROOT / "lib"

DEFAULT_GLSLANG = (
    shutil.which("glslang")
    or shutil.which("glslangValidator")
    or "/tmp/work/glslang/build/StandAlone/glslang"
)

# ---------------------------------------------------------------------------
# Regular expressions. They mirror the parsers named above, not full GLSL.
# ---------------------------------------------------------------------------

FORMAT_CONST_RE = re.compile(r"const int colortex\d+Format = \w+;$")

INCLUDE_RE = re.compile(r'^[ \t]*#[ \t]*include[ \t]+"(?P<path>[^"]*)"[ \t]*(?://.*)?$')
VERSION_RE = re.compile(r'^[ \t]*#[ \t]*version\b.*$')

DEFINE_RE = re.compile(
    r'^(?P<comment>//+)?[ \t]*#[ \t]*define[ \t]+(?P<name>[A-Za-z_][A-Za-z0-9_]*)(?P<rest>.*)$'
)
IFDEF_RE = re.compile(r'^#[ \t]*(?:ifdef|ifndef)[ \t]+(?P<name>[A-Za-z_][A-Za-z0-9_]*)[ \t]*$')
ALLOWED_VALUES_RE = re.compile(r'^//[ \t]*\[(?P<values>[^\]]*)\][ \t]*(?://.*)?$')
VALUE_TOKEN_RE = re.compile(r'^(?P<value>[A-Za-z0-9_.+-]+)[ \t]*(?P<rest>.*)$')

CONST_RE = re.compile(
    r'^const[ \t]+(?P<type>int|float|bool|vec2|vec3|ivec3|vec4)[ \t]+'
    r'(?P<name>[A-Za-z_][A-Za-z0-9_]*)[ \t]*=[ \t]*(?P<value>[A-Za-z0-9_.+-]+)[ \t]*;'
)
DIRECTIVE_RE = re.compile(
    r'/\*[ \t]*(?P<kind>DRAWBUFFERS|RENDERTARGETS)[ \t]*:[ \t]*(?P<value>[^*]*?)\*/'
)
DIRECTIVE_STRICT_RE = re.compile(r'^[0-9]+(,[0-9]+)*$')
SAMPLER_RE = re.compile(
    r'^[ \t]*uniform[ \t]+sampler[A-Za-z0-9]*[ \t]+(?P<name>[A-Za-z_][A-Za-z0-9_]*)'
    r'[ \t]*(?:\[[^\]]*\])?[ \t]*;',
    re.MULTILINE,
)
VARYING_RE = re.compile(
    r'^[ \t]*varying[ \t]+(?P<type>[A-Za-z_][A-Za-z0-9_]*)[ \t]+'
    r'(?P<name>[A-Za-z_][A-Za-z0-9_]*)[ \t]*(?:\[[^\]]*\])?[ \t]*;',
    re.MULTILINE,
)
BLOCK_COMMENT_LINE_RE = re.compile(r'^[ \t]*(/\*|\*|\*/)')
LINE_COMMENT_RE = re.compile(r'//.*$')

# Samplers Iris knows about (net.irisshaders.iris.samplers.IrisSamplers), plus
# the colortex range it binds by index.
KNOWN_SAMPLERS = {
    "gtexture", "gcolor", "texture", "tex", "lightmap", "normals", "specular",
    "noisetex", "depthtex0", "depthtex1", "depthtex2", "gdepthtex",
    "shadowtex0", "shadowtex1", "shadow", "watershadow",
    "shadowcolor0", "shadowcolor1", "shadowcolor",
}
KNOWN_SAMPLERS |= {"colortex%d" % index for index in range(16)}

# Identifiers that TransformPatcher refuses to see in pack source because Iris
# uses them internally.
FORBIDDEN_IDENTIFIERS = ("iris_", "irisMain", "moj_import")

# Legacy built-ins that CommonTransformer only rewrites in the vertex stage, so
# using them from a fragment shader is a real error (glslang reports it too, this
# just gives a better message).
VERTEX_ONLY_BUILTINS = (
    "gl_Vertex", "gl_Normal", "gl_MultiTexCoord0", "gl_MultiTexCoord1",
    "gl_NormalMatrix", "gl_NormalScale", "gl_TextureMatrix",
)

# Keys ShaderProperties actually parses. Anything else is logged as an error by
# Iris, so it counts as an error here too.
PROPERTY_KEYS = {
    "sky", "sun", "moon", "stars", "vignette", "underwaterOverlay", "oldLighting",
    "separateAo", "separateEntityDraws", "dynamicHandLight", "oldHandLight",
    "rain.depth", "beacon.beam.depth", "particles.before.deferred",
    "prepareBeforeShadow", "skipAllRendering", "allowConcurrentCompute",
    "supportsColorCorrection", "voxelizeLightBlocks", "frustum.culling",
    "occlusion.culling", "shadowTerrain", "shadowTranslucent", "shadowEntities",
    "shadowPlayer", "shadowBlockEntities", "shadowLightBlockEntities",
    "shadow.enabled", "dhShadow.enabled", "clouds", "sliders", "screen",
    "screen.columns", "fallbackTex", "texture.noise",
}
# Keys whose value has to be a boolean literal for Iris to accept them.
BOOLEAN_PROPERTIES = {
    "sky", "sun", "moon", "stars", "vignette", "underwaterOverlay", "oldLighting",
    "separateAo", "separateEntityDraws", "rain.depth", "beacon.beam.depth",
    "shadowTerrain", "shadowTranslucent", "shadowEntities", "shadowPlayer",
    "shadowBlockEntities", "shadowLightBlockEntities", "shadow.enabled",
    "dhShadow.enabled", "prepareBeforeShadow", "particles.before.deferred",
    "allowConcurrentCompute", "supportsColorCorrection", "voxelizeLightBlocks",
    "frustum.culling", "occlusion.culling", "skipAllRendering", "dynamicHandLight",
    "oldHandLight",
}
PROPERTY_PREFIX_KEYS = (
    "screen.", "profile.", "program.", "alphaTest.", "blend.", "scale.", "flip.",
    "bufferObject.", "customTexture.", "image.", "indirect.", "size.buffer.",
    "texture.", "uniform.", "variable.", "backFace.",
)
BOOLEAN_PROPERTY_VALUES = {"true", "false", "1", "0"}
CLOUDS_VALUES = {"off", "fast", "fancy"}

# Options whose individual values get a label in the language file. Numeric
# options show their raw value, which reads fine, so they are not listed here.
LABELLED_VALUE_OPTIONS = {"WATER_QUALITY", "CLOUD_QUALITY", "BLOOM_QUALITY", "TONEMAP_MODE"}


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

class Report:
    """Collects errors and warnings, grouped so the output stays readable."""

    def __init__(self) -> None:
        self.errors: List[str] = []
        self.warnings: List[str] = []

    def error(self, where: str, message: str) -> None:
        self.errors.append("%s: %s" % (where, message))

    def warn(self, where: str, message: str) -> None:
        self.warnings.append("%s: %s" % (where, message))

    def dump(self) -> None:
        for warning in self.warnings:
            print("  warning: %s" % warning)
        for error in self.errors:
            print("  ERROR:   %s" % error)


# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

@dataclass
class Option:
    kind: str                     # "bool" or "value"
    name: str
    default: str                  # "true"/"false" for booleans, literal for values
    allowed: List[str] = field(default_factory=list)
    location: str = ""


def classify_option_line(text: str) -> Optional[Option]:
    """Mirror OptionAnnotatedSource#parseDefineOption for a single line.

    Returns None for lines that Iris would turn into a diagnostic instead of an
    option, which includes every plain numeric `#define NAME value` (the pack has
    a lot of those, and Iris ignores them quietly).
    """

    stripped = text.strip()

    match = DEFINE_RE.match(stripped)
    if match is None:
        return None

    leading_comment = match.group("comment") is not None
    name = match.group("name")
    rest = match.group("rest").strip()

    # `#define NAME` and `#define NAME // anything` are boolean options.
    if rest == "" or rest.startswith("//"):
        return Option("bool", name, "true" if not leading_comment else "false")

    # A leading comment is only allowed on boolean defines.
    if leading_comment:
        return None

    value_match = VALUE_TOKEN_RE.match(rest)
    if value_match is None:
        return None

    value = value_match.group("value")
    tail = value_match.group("rest").strip()

    # Without an allowed value list this is a plain macro, not an option.
    allowed_match = ALLOWED_VALUES_RE.match(tail)
    if allowed_match is None:
        return None

    return Option("value", name, value, allowed_match.group("values").split())


def relative(path: Path) -> str:
    try:
        return str(path.relative_to(SHADERS_ROOT))
    except ValueError:
        return str(path)


def collect_options(report: Report) -> Tuple[Dict[str, Option], List[str]]:
    """Find every option of the pack and every boolean define reference.

    Mirrors ShaderPackOptions: options are discovered per source file, and a
    boolean option only becomes configurable when at least one file references it
    with `#ifdef NAME` or `#ifndef NAME`. References inside plain `#if` do not
    count (OptionAnnotatedSource#parseIfdef).
    """

    options: Dict[str, Option] = {}
    references: List[str] = []

    sources = sorted(
        list(LIB_ROOT.glob("*.glsl"))
        + list(BODY_ROOT.glob("*.glsl"))
        + list(SHADERS_ROOT.glob("*.vsh"))
        + list(SHADERS_ROOT.glob("*.fsh"))
        + [path for folder, _, _ in DIMENSIONS if folder
           for path in list((SHADERS_ROOT / folder).glob("*.vsh"))
           + list((SHADERS_ROOT / folder).glob("*.fsh"))]
    )

    for source in sources:
        for lineno, text in enumerate(source.read_text(encoding="utf-8").splitlines(), 1):
            stripped = text.strip()

            ifdef = IFDEF_RE.match(stripped)
            if ifdef is not None:
                references.append(ifdef.group("name"))
                continue

            option = classify_option_line(text)
            if option is None:
                continue

            option.location = "%s:%d" % (relative(source), lineno)

            existing = options.get(option.name)
            if existing is not None:
                if (existing.kind, existing.default, existing.allowed) != (
                    option.kind, option.default, option.allowed,
                ):
                    report.error(
                        option.location,
                        "option %s conflicts with the declaration at %s "
                        "(Iris drops ambiguous options)"
                        % (option.name, existing.location),
                    )
                continue

            options[option.name] = option

    return options, sorted(set(references))


# ---------------------------------------------------------------------------
# Include expansion, the way IncludeProcessor does it
# ---------------------------------------------------------------------------

@dataclass
class Line:
    origin: str
    lineno: int
    text: str


def expand_includes(
    path: Path, report: Report, stack: Optional[List[Path]] = None
) -> List[Line]:
    """Expand `#include` recursively, exactly like Iris' IncludeProcessor.

    An include path that starts with `/` is absolute to the pack's `shaders/`
    directory, anything else is relative to the file it appears in.
    """

    stack = list(stack or [])

    if path in stack:
        report.error(
            relative(path), "cyclic include: %s" % " -> ".join(relative(p) for p in stack)
        )
        return []

    stack.append(path)

    lines: List[Line] = []

    for lineno, text in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        match = INCLUDE_RE.match(text)

        if match is None:
            lines.append(Line(relative(path), lineno, text))
            continue

        include = match.group("path")

        if include.startswith("/"):
            target = SHADERS_ROOT / include[1:]
        else:
            target = (path.parent / include).resolve()

        if not target.is_file():
            report.error(
                "%s:%d" % (relative(path), lineno), "include target does not exist: %s" % include
            )
            continue

        lines.extend(expand_includes(target, report, stack))

    stack.pop()

    return lines


def hoist_version(lines: List[Line], where: str, report: Report) -> List[Line]:
    """Move the #version directive to the top, like JcppProcessor does.

    Iris hoists every `#version` line it finds to the top of the file, so a second
    one arriving through an include would end up as a duplicate directive. The
    pack therefore keeps `#version` in the generated wrappers only.
    """

    versions = [(index, line) for index, line in enumerate(lines) if VERSION_RE.match(line.text)]

    if len(versions) != 1:
        report.error(
            where,
            "expected exactly one #version directive after include expansion, found %d (%s)"
            % (len(versions), ", ".join(line.origin for _, line in versions)),
        )

    if not versions:
        return lines

    index, version_line = versions[0]
    rest = [line for position, line in enumerate(lines) if position != index]

    return [version_line] + rest


def apply_overrides(lines: List[Line], overrides: Dict[str, str]) -> List[Line]:
    """Rewrite option values the way OptionAnnotatedSource#edit does."""

    result = list(lines)

    for position, line in enumerate(result):
        option = classify_option_line(line.text)

        if option is None or option.name not in overrides:
            continue

        value = overrides[option.name]

        if option.kind == "bool":
            result[position] = Line(
                line.origin, line.lineno, "#define " + option.name if value else "//#define " + option.name
            )
        else:
            if value not in option.allowed:
                raise SystemExit(
                    "test configuration uses %s=%s, which is not one of the allowed values %s"
                    % (option.name, value, option.allowed)
                )
            result[position] = Line(
                line.origin,
                line.lineno,
                "#define %s %s  //[%s]" % (option.name, value, " ".join(option.allowed)),
            )

    return result


# ---------------------------------------------------------------------------
# Linting the expanded source
# ---------------------------------------------------------------------------

def strip_comments(text: str) -> str:
    """Remove // comments so identifier checks do not trip over prose."""

    return LINE_COMMENT_RE.sub("", text)


def lint_program(
    program: str,
    dimension: str,
    stage: str,
    lines: Sequence[Line],
    report: Report,
) -> Dict[str, Dict[str, str]]:
    """Run the Iris specific checks that no compiler can do for us."""

    where = "%s%s" % (dimension + "/" if dimension else "", program)
    varyings: Dict[str, Dict[str, str]] = {}
    text = "\n".join(line.text for line in lines)
    code_only = "\n".join(strip_comments(line.text) for line in lines)

    for identifier in FORBIDDEN_IDENTIFIERS:
        if re.search(r"\b%s" % re.escape(identifier), code_only):
            for line in lines:
                if identifier in strip_comments(line.text):
                    report.error(
                        "%s:%d" % (line.origin, line.lineno),
                        "%s uses the Iris internal identifier prefix %r, which "
                        "TransformPatcher rejects" % (where, identifier),
                    )
                    break

    if stage == "fragment":
        for builtin in VERTEX_ONLY_BUILTINS:
            if re.search(r"\b%s\b" % builtin, code_only):
                report.error(
                    where,
                    "fragment stage uses %s, which is only available in the vertex "
                    "stage (CommonTransformer does not inject it)" % builtin,
                )

    for match in SAMPLER_RE.finditer(code_only):
        name = match.group("name")
        if name not in KNOWN_SAMPLERS:
            report.error(where, "declares sampler %r, which Iris never binds" % name)

    for match in VARYING_RE.finditer(text):
        varyings[match.group("name")] = {
            "type": match.group("type"),
            "stage": stage,
        }

    # Comment directives: DRAWBUFFERS / RENDERTARGETS.
    for match in DIRECTIVE_RE.finditer(text):
        # CommentDirectiveParser trims the value between the colon and `*/`.
        value = match.group("value").strip()

        if stage != "fragment":
            report.error(
                where,
                "%s directive in a vertex source, Iris only reads directives from "
                "fragment sources (ProgramDirectives)" % match.group("kind"),
            )

        if not DIRECTIVE_STRICT_RE.match(value):
            report.error(
                where,
                "%s directive value %r is not a comma separated list of digits "
                "without spaces (Iris splits on ',' and calls Integer.parseInt on "
                "each part)" % (match.group("kind"), value),
            )

    # Const directives are collected from fragment sources only.
    if stage == "fragment":
        for line in lines:
            stripped = line.text.strip()
            const = CONST_RE.match(stripped)
            if const is None:
                continue
            if BLOCK_COMMENT_LINE_RE.match(line.text) or stripped.startswith("*"):
                report.error(
                    "%s:%d" % (line.origin, line.lineno),
                    "const directive inside a comment block: Iris' ConstDirectiveParser "
                    "reads it, but a texture format has to be written that way while a "
                    "numeric or boolean const must stay outside so that GLSL compiles",
                )

    return varyings


def check_varyings(program: str, dimension: str, vert: Dict[str, Dict[str, str]],
                   frag: Dict[str, Dict[str, str]], report: Report) -> None:
    """Every varying a fragment shader reads has to be written by its vertex shader.

    glslang's link step catches type mismatches, but in the compatibility profile
    a fragment varying that the vertex stage never declares is legal GLSL - it
    simply reads garbage at runtime. Iris' own transformer makes the same
    assumption, so this is checked by hand.
    """

    where = "%s%s" % (dimension + "/" if dimension else "", program)

    for name, info in sorted(frag.items()):
        if name not in vert:
            report.error(
                where,
                "fragment stage declares varying %s (%s) that the vertex stage never "
                "writes; it would read uninitialised data" % (name, info["type"]),
            )
        elif vert[name]["type"] != info["type"]:
            report.error(
                where,
                "varying %s is %s in the vertex stage but %s in the fragment stage"
                % (name, vert[name]["type"], info["type"]),
            )


# ---------------------------------------------------------------------------
# glslang
# ---------------------------------------------------------------------------

STAGE_GUARD_RE = re.compile(
    r'^#\s*if\s+defined\s*\(\s*(HZ_STAGE_VERTEX|HZ_STAGE_FRAGMENT)\s*\)\s*$'
)
OTHER_IF_RE = re.compile(r'^#\s*(?:if|ifdef|ifndef)\b')
ELSE_RE = re.compile(r'^#\s*(?:else|elif)\b')
ENDIF_RE = re.compile(r'^#\s*endif\b')


def select_stage(lines: Sequence[Line], stage_define: str) -> List[Line]:
    """Drop the blocks that belong to the other stage.

    The program bodies are shared between the vertex and the fragment stage and
    select their content with `#if defined(HZ_STAGE_VERTEX)` /
    `#if defined(HZ_STAGE_FRAGMENT)`. Iris compiles the expanded source per stage,
    so the stage specific lint rules have to see the same subset. Conditionals the
    pack does not use for stage selection are treated as always taken, which keeps
    both of their branches under inspection.
    """

    selected: List[Line] = []
    stack: List[Tuple[bool, bool]] = []

    for line in lines:
        text = line.text.strip()

        guard = STAGE_GUARD_RE.match(text)

        if guard is not None:
            stack.append((True, guard.group(1) == stage_define))
            selected.append(line)
        elif OTHER_IF_RE.match(text):
            stack.append((False, True))
            selected.append(line)
        elif ELSE_RE.match(text):
            if stack:
                is_guard, active = stack[-1]
                stack[-1] = (is_guard, (not active) if is_guard else True)
            selected.append(line)
        elif ENDIF_RE.match(text):
            if stack:
                stack.pop()
            selected.append(line)
        elif all(active for _, active in stack):
            selected.append(line)

    return selected


# Uniforms Iris provides to packs (net.irisshaders.iris.uniforms.*, plus the
# matrices MatrixUniforms builds from the "gbuffer"/"shadow" prefixes and the
# "Inverse"/"Previous" suffixes). Declaring a uniform that Iris does not know is
# legal GLSL and compiles fine, but it silently reads zero at runtime, so a typo
# here is a bug no compiler will ever report.
IRIS_UNIFORMS = frozenset("""
    aspectRatio atlasSize viewWidth viewHeight near far
    eyeAltitude eyeBrightness eyeBrightnessSmooth eyePosition relativeEyePosition
    rainStrength rainStrengthS rainStrengthS2 rainStrengthShining rainfall
    wetness burningSmooth blindness blindFactor darknessFactor darknessLightFactor
    constantMood nightVision screenBrightness isEyeInWater isEyeInCave hideGUI
    firstPersonCamera isSpectator isRightHanded playerMood sneakSmooth velocity
    playerLookVector playerBodyVector effectStrength starter
    cameraPosition cameraPositionInt cameraPositionFract
    previousCameraPosition previousCameraPositionInt previousCameraPositionFract
    sunPosition moonPosition shadowLightPosition upPosition sunAngle shadowAngle
    timeAngle moonPhase moonBrightness dawnDusk
    worldTime worldDay currentTime currentDate currentYearTime frameCounter
    frameTimeCounter frameTimeSmooth frameTime cloudTime cloudHeight
    skyColor fogColor fogMode fogDensity fogStart fogEnd fogShape ambientLight
    bedrockLevel heightLimit logicalHeightLimit hasCeiling hasSkylight
    heldItemId heldItemId2 heldBlockLightValue heldBlockLightValue2
    heldBlockLightColor heldBlockLightColor2 currentRenderedItemId
    entityId blockEntityId currentSelectedBlockId currentSelectedBlockPos
    renderStage
    biome biome_category biome_precipitation temperature humidity isRainy isSnowy
    isDry is_burning is_hurt is_invisible is_on_ground is_sneaking is_sprinting
    isInSwamp thunderStrength lightningBoltPosition
    currentPlayerHealth maxPlayerHealth currentPlayerAir maxPlayerAir
    currentPlayerArmor maxPlayerArmor currentPlayerHunger maxPlayerHunger
    currentColorSpace colorSpace
    dhRenderDistance dhNearPlane dhFarPlane
    gbufferModelView gbufferModelViewInverse gbufferPreviousModelView
    gbufferProjection gbufferProjectionInverse gbufferPreviousProjection
    shadowModelView shadowModelViewInverse shadowProjection shadowProjectionInverse
    entityColor
""".split())

UNIFORM_RE = re.compile(
    r'^[ \t]*uniform[ \t]+(?P<type>[A-Za-z_][A-Za-z0-9_]*)[ \t]+'
    r'(?P<name>[A-Za-z_][A-Za-z0-9_]*)[ \t]*(?:\[[^\]]*\])?[ \t]*;',
    re.MULTILINE,
)


def collect_declared_uniforms() -> List[str]:
    names = set()

    for source in list(LIB_ROOT.glob("*.glsl")) + list(BODY_ROOT.glob("*.glsl")):
        text = "\n".join(
            strip_comments(line) for line in source.read_text(encoding="utf-8").splitlines()
        )

        for match in UNIFORM_RE.finditer(text):
            if not match.group("type").startswith("sampler"):
                names.add(match.group("name"))

    return sorted(names)


def check_uniforms(report: Report) -> None:
    """Every declared uniform has to be one Iris actually sets."""

    declared: Dict[str, str] = {}

    sources = sorted(
        list(LIB_ROOT.glob("*.glsl")) + list(BODY_ROOT.glob("*.glsl"))
    )

    for source in sources:
        text = "\n".join(
            strip_comments(line) for line in source.read_text(encoding="utf-8").splitlines()
        )

        for match in UNIFORM_RE.finditer(text):
            uniform_type = match.group("type")

            if uniform_type.startswith("sampler"):
                continue

            name = match.group("name")

            if name not in IRIS_UNIFORMS:
                report.error(
                    relative(source),
                    "declares uniform %s %s, which Iris does not provide; it would "
                    "compile but always read zero" % (uniform_type, name),
                )

            if name in declared and declared[name] != uniform_type:
                report.error(
                    relative(source),
                    "uniform %s is declared as %s here and as %s in %s"
                    % (name, uniform_type, declared[name], name),
                )

            declared[name] = uniform_type

GLSLANG_ERROR_RE = re.compile(r'^(?P<level>ERROR|WARNING):\s*(?P<file>[^\s:]+):(?P<line>\d+):\s*(?P<message>.*)$')


def run_glslang(
    binary: str,
    vert_path: Path,
    frag_path: Path,
    label: str,
    vert_lines: Sequence[Line],
    frag_lines: Sequence[Line],
    report: Report,
) -> bool:
    """Compile and link one program pair. Returns True when it was clean."""

    command = [binary, "-l", str(vert_path), str(frag_path)]

    try:
        completed = subprocess.run(command, capture_output=True, text=True, timeout=180)
    except (OSError, subprocess.TimeoutExpired) as error:
        report.error(label, "could not run glslang (%s): %s" % (binary, error))
        return False

    output = (completed.stdout or "") + (completed.stderr or "")
    mappings = {vert_path.name: vert_lines, frag_path.name: frag_lines}
    problems = []

    for raw in output.splitlines():
        line = raw.strip()

        match = GLSLANG_ERROR_RE.match(line)
        if match is not None:
            mapped = mappings.get(Path(match.group("file")).name)
            number = int(match.group("line"))

            location = match.group("file")
            if mapped is not None and 1 <= number <= len(mapped):
                source = mapped[number - 1]
                location = "%s:%d" % (source.origin, source.lineno)

            problems.append("%s: %s" % (location, match.group("message")))
            continue

        if line.startswith("ERROR") or line.startswith("error"):
            problems.append(line)

    for problem in problems:
        report.error(label, problem)

    return completed.returncode == 0 and not problems


# ---------------------------------------------------------------------------
# Configurations
# ---------------------------------------------------------------------------

@dataclass
class Configuration:
    name: str
    overrides: Dict[str, str]
    dimensions: Tuple[str, ...]


def build_configurations(options: Dict[str, Option]) -> List[Configuration]:
    """A handful of option combinations that between them exercise every #if branch."""

    all_dimensions = tuple(folder for folder, _, _ in DIMENSIONS)
    root_only = ("",)

    booleans = [name for name, option in options.items() if option.kind == "bool"]
    value_options = {name: option for name, option in options.items() if option.kind == "value"}

    def first(name: str) -> str:
        return value_options[name].allowed[0]

    def last(name: str) -> str:
        return value_options[name].allowed[-1]

    minimal = {name: "false" for name in booleans}
    minimal.update({name: first(name) for name in ("CLOUD_QUALITY", "WATER_QUALITY", "BLOOM_QUALITY")})

    maximal = {name: "true" for name in booleans}
    maximal.update({name: last(name) for name in ("CLOUD_QUALITY", "WATER_QUALITY", "BLOOM_QUALITY")})

    # The shipped defaults, in all three dimensions.
    configurations = [Configuration("default", {}, all_dimensions)]

    # Everything that can be switched off is switched off: this is the code path
    # the Low profile takes, and the Nether/End paths with the least features.
    configurations.append(Configuration("minimal", minimal, all_dimensions))

    # Everything on, at the highest quality.
    configurations.append(Configuration("maximal", maximal, root_only))

    # Individual branches that the two extremes above cannot reach at once.
    configurations.append(
        Configuration(
            "alt-modes",
            {
                "TONEMAP_MODE": value_options["TONEMAP_MODE"].allowed[0],
                "WATER_QUALITY": last("WATER_QUALITY"),
                "CLOUD_QUALITY": first("CLOUD_QUALITY"),
                "BLOOM_QUALITY": first("BLOOM_QUALITY"),
                "SHADOW_DISTORTION": first("SHADOW_DISTORTION"),
                "CLOUD_SPEED": first("CLOUD_SPEED"),
                "WATER_WAVE_STRENGTH": first("WATER_WAVE_STRENGTH"),
            },
            root_only,
        )
    )
    configurations.append(
        Configuration(
            "alt-modes-2",
            {
                "TONEMAP_MODE": last("TONEMAP_MODE"),
                "SHADOW_RESOLUTION": last("SHADOW_RESOLUTION"),
                "SHADOW_SOFTNESS": last("SHADOW_SOFTNESS"),
                "SHADOW_SAMPLES": first("SHADOW_SAMPLES"),
                "BLOCKLIGHT_FALLOFF": last("BLOCKLIGHT_FALLOFF"),
                "GAMMA": first("GAMMA"),
            },
            root_only,
        )
    )

    return configurations


# ---------------------------------------------------------------------------
# Structure checks
# ---------------------------------------------------------------------------

def check_layout(report: Report) -> None:
    """Program bodies, wrappers and dimension folders."""

    if not SHADERS_ROOT.is_dir():
        raise SystemExit("missing pack directory %s" % SHADERS_ROOT)

    for name in PROGRAMS:
        body = BODY_ROOT / ("%s.glsl" % name)

        if not body.is_file():
            report.error(relative(body), "program body is missing")
            continue

        text = body.read_text(encoding="utf-8")

        if VERSION_RE.search("\n".join(text.splitlines())):
            report.error(
                relative(body),
                "program bodies must not contain a #version directive: the generated "
                "wrappers provide it, and Iris hoists every #version it finds, so a "
                "second one becomes a duplicate directive",
            )

        for folder, define, label in DIMENSIONS:
            for extension, stage_define, stage_name in STAGES:
                wrapper_path = (SHADERS_ROOT / folder / ("%s.%s" % (name, extension))) if folder \
                    else SHADERS_ROOT / ("%s.%s" % (name, extension))

                if not wrapper_path.is_file():
                    report.error(
                        relative(wrapper_path),
                        "missing %s wrapper for %s; Iris does not merge dimension "
                        "folders with the pack root, so every folder needs every "
                        "program (ShaderPack#getProgramSet)" % (extension, label),
                    )

    for required in ("shaders.properties", "block.properties", os.path.join("lang", "en_us.lang")):
        path = SHADERS_ROOT / required
        if not path.is_file():
            report.error(relative(path), "required pack file is missing")


def check_wrappers_in_sync(report: Report) -> None:
    """The committed wrappers must equal what the generator writes."""

    for name in PROGRAMS:
        for folder, define, label in DIMENSIONS:
            target = SHADERS_ROOT / folder if folder else SHADERS_ROOT

            for extension, stage_define, stage_name in STAGES:
                path = target / ("%s.%s" % (name, extension))

                if not path.is_file():
                    continue

                expected = build_wrapper(name, extension, stage_define, stage_name, label, define)
                actual = path.read_text(encoding="utf-8")

                if actual != expected:
                    report.error(
                        relative(path),
                        "wrapper is out of date, run: python3 tools/generate_programs.py",
                    )


def check_unintended_options(options: Dict[str, Option], references: Sequence[str],
                             report: Report) -> None:
    """Catch macros that would show up in the settings menu by accident."""

    declared = set(options)
    registered = {name for name in references if name in declared}

    # HZ_STAGE_* and the include guards are defined by the wrappers and the
    # libraries; they must never be confirmed by an #ifdef, or Iris turns them
    # into user toggles that break the pack when flipped.
    internal = [name for name in registered if name.startswith(("HZ_", "DIM_"))]

    for name in internal:
        report.error(
            options[name].location,
            "%s is referenced with #ifdef/#ifndef somewhere, so Iris registers it as "
            "a user configurable option; use `#if defined(%s)` instead" % (name, name),
        )

    # HZ_* are the include guards and the stage selectors written by the wrapper
    # generator, DIM_* mark the dimension folder. None of them may ever be
    # confirmed by an #ifdef, and none of them are meant to be menu entries.
    internal_prefixes = ("HZ_", "DIM_")

    unreferenced = sorted(
        name for name, option in options.items()
        if option.kind == "bool" and name not in references
        and not name.startswith(internal_prefixes)
    )

    for name in unreferenced:
        report.error(
            options[name].location,
            "boolean option %s is never referenced with #ifdef or #ifndef, so Iris "
            "will not register it and it cannot be toggled in the menu" % name,
        )

    for name, option in sorted(options.items()):
        if option.kind == "value":
            if option.default not in option.allowed:
                report.error(
                    option.location,
                    "default value %s of %s is not in the allowed value list %s"
                    % (option.default, name, option.allowed),
                )


# ---------------------------------------------------------------------------
# Properties checks
# ---------------------------------------------------------------------------

def parse_properties(path: Path) -> List[Tuple[int, str, str]]:
    """Read a java style properties file, ignoring comments and continuations."""

    entries: List[Tuple[int, str, str]] = []
    pending: Optional[Tuple[int, str]] = None

    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.rstrip()

        if pending is not None:
            start, key = pending
            pending = None

            if line.endswith("\\"):
                entries.append((start, key, line[:-1].strip()))
                continue

            entries.append((start, key, line.strip()))
            continue

        stripped = line.strip()

        if not stripped or stripped.startswith("#") or stripped.startswith("!"):
            continue

        separator = len(stripped)
        for index, character in enumerate(stripped):
            if character in "=:" and (index == 0 or stripped[index - 1] != "\\"):
                separator = index
                break

        key = stripped[:separator].strip()
        value = stripped[separator + 1:].strip()

        if value.endswith("\\"):
            pending = (lineno, key)
            continue

        entries.append((lineno, key, value))

    return entries


def preprocessed_properties_entries(path: Path, options: Dict[str, Option]) -> List[Tuple[int, str, str]]:
    """Emulate PropertiesPreprocessor for the boolean option macros.

    Iris defines every enabled boolean option as an empty macro, so the value of
    `program.<name>.enabled=OPTION` becomes empty while the option is on and stays
    a bare identifier while it is off. `#ifdef` blocks are resolved here as well.
    """

    enabled = {name for name, option in options.items()
               if option.kind == "bool" and option.default == "true"}

    result: List[Tuple[int, str, str]] = []
    stack: List[bool] = []

    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = raw.strip()

        if stripped.startswith("#ifdef "):
            stack.append(stripped[len("#ifdef "):].strip() in enabled)
            continue
        if stripped.startswith("#ifndef "):
            stack.append(stripped[len("#ifndef "):].strip() not in enabled)
            continue
        if stripped.startswith("#if "):
            report_needs_ifdef(path, lineno, stripped)
            stack.append(True)
            continue
        if stripped.startswith("#else"):
            if stack:
                stack[-1] = not stack[-1]
            continue
        if stripped.startswith("#endif"):
            if stack:
                stack.pop()
            continue

        if stack and not all(stack):
            continue

        result.append((lineno, raw))

    entries: List[Tuple[int, str, str]] = []

    for lineno, raw in result:
        text = raw.strip()

        if not text or text.startswith("#"):
            continue

        separator = len(text)
        for index, character in enumerate(text):
            if character in "=:" and (index == 0 or text[index - 1] != "\\"):
                separator = index
                break

        key = text[:separator].strip()
        value = text[separator + 1:].strip()

        # A boolean option used as a value expands to nothing while it is enabled.
        tokens = [token for token in value.split() if token not in enabled]
        value = " ".join(tokens) if tokens else ""

        entries.append((lineno, key, value))

    return entries


def report_needs_ifdef(path: Path, lineno: int, text: str) -> None:
    print("  note:    %s:%d: `#if` in a properties file is evaluated by Iris' "
          "preprocessor with empty macros; prefer #ifdef (%s)" % (relative(path), lineno, text))


def check_shader_properties(options: Dict[str, Option], report: Report) -> Dict[str, object]:
    """Validate shaders.properties against ShaderProperties' parsing rules.

    ShaderProperties reads the same file twice: once through the option
    preprocessor, whose entries drive everything except the menu, and once
    unprocessed, whose entries drive `sliders`, `screen*` and `profile.*`
    (the `original.forEach` block at the end of the constructor). Both views are
    reproduced here, because a boolean option used as a value is macro expanded to
    nothing in the first view only.
    """

    path = SHADERS_ROOT / "shaders.properties"

    if not path.is_file():
        report.error("shaders.properties", "file is missing")
        return {}

    preprocessed = preprocessed_properties_entries(path, options)
    original = parse_properties(path)

    profiles: Dict[str, List[str]] = {}
    screens: Dict[str, List[str]] = {}
    sliders: List[str] = []

    menu_keys = ("sliders", "screen")

    # --- keys read from the unprocessed file ---------------------------------
    for lineno, key, value in original:
        where = "%s:%d" % (relative(path), lineno)

        if key == "sliders":
            sliders = value.split()

            for option_name in sliders:
                if option_name not in options:
                    report.error(where, "sliders lists unknown option %s" % option_name)
                elif options[option_name].kind != "value":
                    report.error(where, "sliders lists boolean option %s, only value "
                                        "options can be sliders" % option_name)

        elif key == "screen":
            screens[""] = value.split()

        elif key == "screen.columns":
            if not value.isdigit():
                report.error(where, "screen.columns expects an integer, got %r" % value)

        elif key.startswith("screen."):
            screen_id = key[len("screen."):]

            if screen_id.endswith(".columns"):
                if not value.isdigit():
                    report.error(where, "%s expects an integer, got %r" % (key, value))
                continue

            screens[screen_id] = value.split()

        elif key.startswith("profile."):
            profiles[key[len("profile."):]] = value.split()

    # Profile inheritance (`profile.OTHER` tokens) can point forwards in the file,
    # so those references are checked once every profile is known.
    for name, tokens in profiles.items():
        for index, token in enumerate(tokens):
            where = "%s (profile.%s)" % (relative(path), name)

            if token.startswith("!program."):
                if token[len("!program."):] not in PROGRAMS:
                    report.error(where, "disables unknown program %s"
                                 % token[len("!program."):])
            elif token.startswith("profile."):
                if token[len("profile."):] not in profiles:
                    report.error(where, "inherits unknown profile %s"
                                 % token[len("profile."):])
            elif token.startswith("!"):
                if token[1:] not in options:
                    report.error(where, "references unknown option %s" % token[1:])
                elif options[token[1:]].kind != "bool":
                    report.error(where, "negates value option %s, which Profile.parse "
                                        "would store as %s=false" % (token[1:], token[1:]))
            elif "=" in token or ":" in token:
                option_name, option_value = re.split("[=:]", token, 1)

                if option_name not in options:
                    report.error(where, "references unknown option %s" % option_name)
                elif options[option_name].kind != "value":
                    report.error(where, "assigns a value to boolean option %s" % option_name)
                elif option_value not in options[option_name].allowed:
                    report.error(where, "sets %s=%s, which is not one of %s"
                                 % (option_name, option_value, options[option_name].allowed))
            elif token not in options:
                report.error(where, "references unknown option %s" % token)
            elif options[token].kind != "bool":
                report.error(where, "lists value option %s without a value, which "
                                    "Profile.parse ignores with a warning" % token)

    # --- keys read from the preprocessed file --------------------------------
    for lineno, key, value in preprocessed:
        where = "%s:%d" % (relative(path), lineno)

        if not key or key == "sliders" or key == "screen" or key.startswith(menu_keys[1] + ".") \
                or key.startswith("profile."):
            continue

        if key in PROPERTY_KEYS:
            if key in BOOLEAN_PROPERTIES:
                if value not in BOOLEAN_PROPERTY_VALUES:
                    report.error(where, "%s expects true/false, got %r" % (key, value))
            elif key == "clouds" and value not in CLOUDS_VALUES:
                report.error(where, "clouds expects one of %s, got %r"
                             % (sorted(CLOUDS_VALUES), value))
            elif key == "screen.columns" and not value.isdigit():
                report.error(where, "screen.columns expects an integer, got %r" % value)
            continue

        if key.startswith("program."):
            parts = key.split(".")

            if len(parts) != 3 or parts[2] != "enabled":
                report.error(where, "unsupported program property %r, Iris only reads "
                                    "program.<name>.enabled" % key)
                continue

            if parts[1] not in PROGRAMS:
                report.error(where, "program.%s.enabled names a program the pack does "
                                    "not ship" % parts[1])
                continue

            for token in re.split(r"[&|()! ]+", value):
                if not token or token in {"true", "false", "0", "1"}:
                    continue
                if token not in options:
                    report.error(where, "program.%s.enabled references unknown option %s "
                                        "(BooleanParser resolves it to false, so the "
                                        "program would never run)" % (parts[1], token))
                elif options[token].kind != "bool":
                    report.warn(where, "program.%s.enabled references value option %s, "
                                       "which expands to its value" % (parts[1], token))
            continue

        if key.startswith(PROPERTY_PREFIX_KEYS):
            continue

        report.error(where, "unknown property key %r; Iris logs this as an error and "
                            "ignores the line" % key)

    # --- menu resolution -----------------------------------------------------
    for screen_id, elements in screens.items():
        label = "screen%s" % ("." + screen_id if screen_id else "")

        for element in elements:
            if element in {"<empty>", "<profile>", "*"}:
                continue
            if element.startswith("[") and element.endswith("]"):
                target = element[1:-1]
                if target not in screens:
                    report.error("%s (%s)" % (relative(path), label),
                                 "links to [%s], but there is no screen.%s= entry"
                                 % (target, target))
                continue
            if element not in options:
                report.error("%s (%s)" % (relative(path), label),
                             "lists %r, which is not a pack option; Iris logs a warning "
                             "and shows an empty slot" % element)

    placed = set()
    for elements in screens.values():
        placed.update(element for element in elements if element in options)

    has_star = any("*" in elements for elements in screens.values())

    for name in sorted(options):
        if name.startswith("HZ_") or name.startswith("DIM_"):
            continue
        if name not in placed and not has_star:
            report.warn(relative(path), "option %s is not listed on any screen" % name)

    if not profiles:
        report.error(relative(path), "no profile.* entries, but the pack advertises "
                                     "quality profiles")

    for name in ("LOW", "MEDIUM", "HIGH"):
        if name not in profiles:
            report.error(relative(path), "profile.%s is missing" % name)

    # Two profiles that could both match the same option values would make the
    # reported profile depend on Iris' internal sort order.
    names = sorted(profiles)
    for index, first in enumerate(names):
        for second in names[index + 1:]:
            a, b = dict(), dict()

            for token in profiles[first]:
                if token.startswith("!") or "=" in token or ":" in token \
                        or token.startswith("profile.") or token.startswith("!program."):
                    continue

            if is_subset(profiles[first], profiles[second]):
                report.warn(relative(path), "profile.%s constraints are a subset of "
                                            "profile.%s, so both can match at once"
                            % (first, second))

    return {"profiles": profiles, "screens": screens, "sliders": sliders}


def profile_constraints(tokens: Iterable[str]) -> Dict[str, str]:
    constraints: Dict[str, str] = {}

    for token in tokens:
        if token.startswith("!program.") or token.startswith("profile."):
            continue
        if token.startswith("!"):
            constraints[token[1:]] = "false"
        elif "=" in token:
            name, value = token.split("=", 1)
            constraints[name] = value
        elif ":" in token:
            name, value = token.split(":", 1)
            constraints[name] = value
        else:
            constraints[token] = "true"

    return constraints


def is_subset(first: Iterable[str], second: Iterable[str]) -> bool:
    a, b = profile_constraints(first), profile_constraints(second)

    return bool(a) and all(b.get(name) == value for name, value in a.items())


def check_block_properties(report: Report) -> None:
    """Validate block.properties against BlockEntry#parse."""

    path = SHADERS_ROOT / "block.properties"

    if not path.is_file():
        report.error("block.properties", "file is missing")
        return

    ids = set()

    for lineno, key, value in parse_properties(path):
        where = "%s:%d" % (relative(path), lineno)

        if not key.startswith("block.") and not key.startswith("layer."):
            report.error(where, "unknown key %r in block.properties" % key)
            continue

        suffix = key.split(".", 1)[1]

        if not suffix.isdigit():
            report.error(where, "%s must be followed by an integer id, got %r"
                         % (key.split(".")[0], suffix))
            continue

        if key.startswith("block."):
            ids.add(int(suffix))

        for entry in value.split():
            body = entry[1:] if entry.startswith("%") else entry
            parts = body.split(":")

            if len(parts) > 3:
                report.error(where, "entry %r has too many ':' separated parts" % entry)
                continue

            for part in parts[1:]:
                if "=" in part and len(part.split("=")) != 2:
                    report.error(where, "entry %r has a malformed property filter, "
                                        "expected key=value" % entry)

            if not parts[0] or (len(parts) > 1 and not parts[1].split("=")[0]):
                report.error(where, "entry %r has an empty namespace or path" % entry)

    # The ids lib/material.glsl compares against have to be defined here, because
    # shipping block.properties replaces Iris' legacy id map completely.
    material = LIB_ROOT / "material.glsl"
    if material.is_file():
        for match in re.finditer(r"#define\s+(HZ_BLOCK_[A-Z_]+)\s+(-?[\d.]+)",
                                 material.read_text(encoding="utf-8")):
            name, value = match.group(1), match.group(2)
            number = float(value)

            if name == "HZ_BLOCK_NONE":
                continue

            if int(number) not in ids:
                report.error(
                    "lib/material.glsl",
                    "%s is %s but block.properties has no block.%d entry; Iris replaces "
                    "its legacy id map with block.properties as soon as the file exists, "
                    "so the id would never be produced"
                    % (name, value, int(number)),
                )


# ---------------------------------------------------------------------------
# Language file checks
# ---------------------------------------------------------------------------

def check_lang(options: Dict[str, Option], properties: Dict[str, object], report: Report) -> None:
    """Validate shaders/lang/en_us.lang against the keys the widgets look up."""

    path = SHADERS_ROOT / "lang" / "en_us.lang"

    if not path.is_file():
        report.error("lang/en_us.lang", "file is missing")
        return

    translations = {}

    for lineno, key, value in parse_properties(path):
        where = "%s:%d" % (relative(path), lineno)

        if key in translations:
            report.error(where, "duplicate translation key %r" % key)

        translations[key] = value

        if not value.strip():
            report.error(where, "translation %r is empty" % key)

        if "%" in value:
            report.warn(where, "translation %r contains %%; Iris builds the label with "
                               "Component.translatable in some widgets, where a stray "
                               "percent sign can be read as a format specifier" % key)

    real_options = {
        name: option for name, option in options.items()
        if not name.startswith(("HZ_", "DIM_"))
    }

    for name in sorted(real_options):
        if "option.%s" % name not in translations:
            report.warn(relative(path), "missing label option.%s" % name)
        if "option.%s.comment" % name not in translations:
            report.warn(relative(path), "missing tooltip option.%s.comment" % name)

        if real_options[name].kind == "value" and name in LABELLED_VALUE_OPTIONS:
            for value in real_options[name].allowed:
                key = "value.%s.%s" % (name, value)
                if key not in translations:
                    report.error(relative(path), "missing value label %s" % key)

    profiles = properties.get("profiles", {})
    for name in sorted(profiles):
        if "profile.%s" % name not in translations:
            report.warn(relative(path), "missing profile label profile.%s" % name)

    screens = properties.get("screens", {})
    for screen_id in sorted(screens):
        if not screen_id:
            continue
        if "screen.%s" % screen_id not in translations:
            report.warn(relative(path), "missing screen label screen.%s" % screen_id)

    # Keys that reference something the pack does not have are usually typos.
    for key in sorted(translations):
        parts = key.split(".")

        if parts[0] == "option" and len(parts) >= 2 and parts[1] not in real_options:
            report.warn(relative(path), "translation %r refers to an option the pack "
                                        "does not define" % key)
        elif parts[0] == "value" and len(parts) >= 2 and parts[1] not in real_options:
            report.warn(relative(path), "translation %r refers to an option the pack "
                                        "does not define" % key)
        elif parts[0] == "profile" and len(parts) == 2 and parts[1] not in profiles \
                and parts[1] != "comment":
            report.warn(relative(path), "translation %r refers to a profile the pack "
                                        "does not define" % key)
        elif parts[0] == "screen" and len(parts) == 2 and parts[1] not in screens:
            report.warn(relative(path), "translation %r refers to a screen the pack "
                                        "does not define" % key)


# ---------------------------------------------------------------------------
# Zip layout
# ---------------------------------------------------------------------------

def check_zip(zip_path: Path, report: Report) -> None:
    """The archive has to unpack straight into .minecraft/shaderpacks."""

    import zipfile

    if not zip_path.is_file():
        report.error(str(zip_path), "zip does not exist, run: python3 tools/build_zip.py")
        return

    with zipfile.ZipFile(zip_path) as archive:
        names = archive.namelist()

        if not names:
            report.error(str(zip_path), "zip is empty")
            return

        roots = {name.split("/")[0] for name in names if name}

        if roots != {"shaders"}:
            report.error(
                str(zip_path),
                "the archive has to contain exactly one top level directory named "
                "`shaders`, found %s" % sorted(roots),
            )

        required = [
            "shaders/shaders.properties",
            "shaders/block.properties",
            "shaders/lang/en_us.lang",
        ]
        required += ["shaders/programs/%s.glsl" % name for name in PROGRAMS]
        required += [
            "shaders/%s%s.%s" % (folder + "/" if folder else "", name, extension)
            for folder, _, _ in DIMENSIONS
            for name in PROGRAMS
            for extension, _, _ in STAGES
        ]
        required += ["shaders/lib/%s" % path.name for path in sorted(LIB_ROOT.glob("*.glsl"))]

        missing = [entry for entry in required if entry not in names]

        for entry in missing:
            report.error(str(zip_path), "zip is missing %s" % entry)

        for name in names:
            base = os.path.basename(name)
            if base in {".DS_Store", "Thumbs.db"} or name.startswith("__MACOSX") \
                    or base.endswith(".swp"):
                report.error(str(zip_path), "zip contains junk entry %s" % name)

        # The real end to end test: unpack the archive somewhere else and resolve
        # every #include from inside it. A library that made it into the repository
        # but not into the archive would only fail at runtime, when Iris tries to
        # compile a program that includes it.
        with tempfile.TemporaryDirectory(prefix="horizon-pack-") as temporary:
            root = Path(temporary)

            try:
                archive.extractall(root, filter="data")
            except TypeError:
                archive.extractall(root)

            shaders = root / "shaders"
            checked = 0

            for path in sorted(shaders.rglob("*")):
                if path.suffix not in {".glsl", ".vsh", ".fsh"} or not path.is_file():
                    continue

                for lineno, text in enumerate(
                    path.read_text(encoding="utf-8").splitlines(), 1
                ):
                    include = INCLUDE_RE.match(text)

                    if include is None:
                        continue

                    target_path = include.group("path")
                    checked += 1

                    if target_path.startswith("/"):
                        resolved = shaders / target_path[1:]
                    else:
                        resolved = (path.parent / target_path).resolve()

                    if not resolved.is_file():
                        report.error(
                            "%s (inside %s):%d" % (path.relative_to(root), zip_path.name, lineno),
                            "include %r does not resolve inside the archive" % target_path,
                        )

            if checked == 0:
                report.error(str(zip_path), "no #include directives found in the "
                                            "archive, which cannot be right")


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def validate_glsl(
    glslang: str,
    configurations: Sequence[Configuration],
    report: Report,
    keep: Optional[Path],
) -> int:
    """Compile and link every program for every configuration."""

    compiled = 0

    with tempfile.TemporaryDirectory(prefix="horizon-shaders-") as temporary:
        workspace = Path(temporary)

        for configuration in configurations:
            for folder, define, label in DIMENSIONS:
                if folder not in configuration.dimensions:
                    continue

                for name in PROGRAMS:
                    source = SHADERS_ROOT / folder / ("%s.vsh" % name) if folder \
                        else SHADERS_ROOT / ("%s.vsh" % name)
                    fragment = SHADERS_ROOT / folder / ("%s.fsh" % name) if folder \
                        else SHADERS_ROOT / ("%s.fsh" % name)

                    for stage_path in (source, fragment):
                        if not stage_path.is_file():
                            report.error(
                                "%s%s" % (folder + "/" if folder else "", name),
                                "missing %s" % stage_path.name,
                            )

                    if not source.is_file() or not fragment.is_file():
                        continue

                    stage_lines = {}

                    for stage_path, stage in ((source, "vertex"), (fragment, "fragment")):
                        lines = expand_includes(stage_path, report)
                        lines = hoist_version(
                            lines,
                            "%s%s.%s" % (folder + "/" if folder else "", name, stage_path.suffix[1:]),
                            report,
                        )
                        lines = apply_overrides(lines, configuration.overrides)
                        stage_lines[stage] = lines

                        selected = select_stage(
                            lines, "HZ_STAGE_VERTEX" if stage == "vertex" else "HZ_STAGE_FRAGMENT"
                        )
                        stage_lines[stage + "_selected"] = selected

                        varyings = lint_program(name, folder, stage, selected, report)
                        stage_lines[stage + "_varyings"] = varyings

                    check_varyings(
                        name, folder,
                        stage_lines["vertex_varyings"],
                        stage_lines["fragment_varyings"],
                        report,
                    )

                    prefix = "%s_%s_%s" % (
                        configuration.name, folder or "overworld", name
                    )
                    vert_path = workspace / (prefix + ".vert")
                    frag_path = workspace / (prefix + ".frag")

                    for path, stage in ((vert_path, "vertex"), (frag_path, "fragment")):
                        # Iris consumes `const int colortexNFormat = X;` as a pack
                        # directive and strips it before the GLSL compiler ever
                        # sees the source (GLSL has no string type, so the format
                        # rides on a const int). Blank the lines instead of
                        # dropping them so glslang line numbers stay aligned.
                        path.write_text(
                            "\n".join(
                                "" if FORMAT_CONST_RE.match(line.text) else line.text
                                for line in stage_lines[stage]
                            ) + "\n",
                            encoding="utf-8",
                        )

                        if keep is not None:
                            destination = keep / path.name
                            destination.parent.mkdir(parents=True, exist_ok=True)
                            shutil.copyfile(path, destination)

                    run_glslang(
                        glslang,
                        vert_path,
                        frag_path,
                        "%s [%s%s]" % (name, configuration.name, "/" + folder if folder else ""),
                        stage_lines["vertex"],
                        stage_lines["fragment"],
                        report,
                    )

                    compiled += 1

    return compiled


def main(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--glslang", default=DEFAULT_GLSLANG,
                        help="glslang validator binary (default: %(default)s)")
    parser.add_argument("--zip", default=None,
                        help="also check the layout of this pack archive")
    parser.add_argument("--keep-expanded", default=None, metavar="DIR",
                        help="write the expanded sources here instead of a temp dir")
    parser.add_argument("--skip-glsl", action="store_true",
                        help="only run the structure, properties and language checks")
    arguments = parser.parse_args(argv)

    report = Report()

    print("Horizon Shaders validation")
    print("==========================")

    print("\n[1/6] pack layout")
    check_layout(report)
    check_wrappers_in_sync(report)

    print("[2/6] shader options")
    options, references = collect_options(report)
    check_unintended_options(options, references, report)

    boolean_count = sum(1 for option in options.values() if option.kind == "bool")
    value_count = len(options) - boolean_count
    print("      %d options (%d boolean, %d value), %d of them confirmed by an "
          "#ifdef/#ifndef reference" % (len(options), boolean_count, value_count,
                                        len([name for name in references if name in options])))

    properties: Dict[str, object] = {}

    print("      %d uniforms declared, all of them provided by Iris"
          % len(collect_declared_uniforms()))

    print("[3/6] shaders.properties")
    properties = check_shader_properties(options, report)

    print("[4/6] block.properties")
    check_block_properties(report)

    print("[5/6] lang/en_us.lang")
    check_lang(options, properties, report)

    compiled = 0

    if not arguments.skip_glsl:
        if not Path(arguments.glslang).exists() and not shutil.which(arguments.glslang):
            raise SystemExit(
                "glslang not found at %r. Install glslang-tools, or pass --glslang, "
                "or run with --skip-glsl." % arguments.glslang
            )

        keep = Path(arguments.keep_expanded) if arguments.keep_expanded else None

        configurations = build_configurations(options)

        print("[6/6] glslang (%s)" % Path(arguments.glslang).name)
        for configuration in configurations:
            print("      configuration %s: %d dimension folder(s)"
                  % (configuration.name, len(configuration.dimensions)))

        compiled = validate_glsl(arguments.glslang, configurations, report, keep)
        print("      compiled and linked %d program pairs" % compiled)
    else:
        print("[6/6] glslang: skipped")

    if arguments.zip:
        print("\nzip layout: %s" % arguments.zip)
        check_zip(Path(arguments.zip), report)

    print("")
    report.dump()

    if report.warnings:
        print("\n%d warning(s)" % len(report.warnings))

    if report.errors:
        print("%d error(s)" % len(report.errors))
        return 1

    print("all checks passed")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
