# Horizon Shaders

A complete shader pack for **[Iris](https://irisshaders.net)** on **Minecraft Java
Edition 1.21.1** (with Sodium). Real shadow mapping, deferred water with
refraction, reflections and foam, a procedural sky with sun, moon phases and
stars, a ray marched cloud layer, dimension aware fog, and a bloom / tonemap /
colour grade post pipeline with an optional temporal filter.

Everything in the pack is real GLSL that compiles: 23 programs, 16 shared
libraries, three dimension folders, and no placeholder stages.

```
HorizonShaders.zip
└── shaders/                      <- the archive root is the shaders folder
    ├── shaders.properties        <- Iris pack properties
    ├── block.properties          <- block material ids
    ├── lang/en_us.lang           <- settings menu strings
    ├── lib/*.glsl                <- shared code (16 files)
    ├── programs/*.glsl           <- one body per program (23 files)
    ├── <program>.vsh / .fsh      <- Overworld wrappers (23 x 2)
    ├── world-1/                  <- Nether, same 23 programs
    └── world1/                   <- End, same 23 programs
```

---

## Installing

1. Install Minecraft Java 1.21.1 with **[Sodium](https://modrinth.com/mod/sodium)**
   and **[Iris](https://modrinth.com/mod/iris)**. Iris is a Fabric/NeoForge mod;
   this pack is not an OptiFine pack and no mod code ships with it.
2. Copy `HorizonShaders.zip` into `.minecraft/shaderpacks/`. **Do not unzip it.**
   The archive already has `shaders/` at its root, which is what Iris looks for.
3. In game: `Options -> Video Settings -> Shader Packs` (or the Iris button in
   the video settings screen), select **HorizonShaders**, press `Apply`.
4. `Shader Pack Settings` opens the menu described under [Settings](#settings).

The zip is produced by GitHub Actions on every push (see
[Building and validating](#building-and-validating)) and can also be built
locally with `python3 tools/build_zip.py`.

---

## What the pack does

### Lighting

| Feature | How |
| --- | --- |
| Sunlight / moonlight | Directional term from `shadowLightPosition`, coloured by sun height (`hzSunColour`: warm at the horizon, neutral at noon, desaturated in storms). Moonlight follows the real lunar phase through `moonPhase`. |
| Ambient / sky light | Hemisphere ambient: sky colour above, ground bounce below, weighted by the sky lightmap value. `CAVE_ADAPT` lifts the ambient floor in the dark using the smoothed eye brightness (`eyeBrightnessSmooth`). |
| Block light | Warm point light from the block lightmap value with a configurable falloff curve, plus `HAND_LIGHT`, a small light attached to the held item. |
| Specular | Analytic Blinn-Phong term (`hzSpecular`) used by water; surfaces get a soft rim from the hemisphere ambient. |
| Emissive blocks | `block.properties` maps lava, magma, fire, lamps and torches to ids that `lib/material.glsl` reads from `mc_Entity.x`, so light sources stay bright even with a saturated lightmap. |
| Fullbright programs | `gbuffers_lightning`, `gbuffers_armor_glint` and `gbuffers_spidereyes` skip lightmap shading entirely and get additive fog instead, which is what vanilla expects from those render types. |

The pack computes light from the lightmap **coordinates** with its own curves
rather than sampling the `lightmap` texture. That keeps the falloff configurable
and avoids a texture fetch per fragment, at the cost of not inheriting vanilla's
exact lightmap tint (night vision, underwater and blindness are handled
explicitly through their uniforms).

### Shadows

Real shadow mapping - a depth only pass rendered from the light direction into
`shadowtex0` / `shadowtex1` / `shadowcolor0`. Nothing here is screen space
darkening.

* `SHADOW_RESOLUTION` (512-8192) is fed to Iris as `const int shadowMapResolution`,
  `SHADOW_DISTANCE` as `const float shadowDistance`, and `SUN_PATH_TILT` as
  `const float sunPathRotation`.
* `SHADOW_DISTORTION` warps the orthographic map towards the camera so nearby
  shadows keep precision.
* `SHADOW_BIAS` plus a normal offset (`lib/shadow_math.glsl`) removes acne and
  peter-panning; `SHADOW_SOFTNESS` and `SHADOW_SAMPLES` drive a Poisson disk
  percentage closer filter that rotates per pixel.
* `COLORED_SHADOWS` reads `shadowcolor0` where `shadowtex0` and `shadowtex1`
  disagree, so stained glass, water and leaves tint the light passing through
  them.
* Shadows fade out before the edge of the map instead of ending in a hard line.
* `SHADOWS=false` removes the whole pass: `shaders.properties` sets
  `shadow.enabled=false`, so Iris never renders the map, and `lib/shadows.glsl`
  stops sampling it.
* The Nether has no shadow mapping (there is no sky light to cast it); the End
  keeps it and lights the map with a cold directional term.

### Water

Water is rendered in two stages, because a world program cannot read `colortex0`
to `colortex3` in Iris (those slots are only bound from `colortex4` upwards
outside fullscreen passes).

1. **`gbuffers_water`** writes the surface into material buffers - animated
   normals, the surface depth, sky light, the water tint and foam - and writes
   transparent black to the colour buffer so that vanilla blending does not
   touch the scene. Depth is still written, which is what the next stage keys on.
2. **`deferred`** resolves those pixels: it refracts the already rendered scene
   through the animated normal using `depthtex1` (rejecting samples that cross
   the water surface, so the hand or rain over water does not smear), applies
   depth based absorption and turbidity, blends a fresnel weighted sky
   reflection, adds the shadow aware sun specular, lights the foam and applies
   fog.

Waves come from several scrolling sine/noise layers (`WATER_QUALITY` sets how
many: 3, 5 or 8), `WATER_WAVE_STRENGTH` scales them,
`WATER_SHININESS` and `WATER_F0` shape the highlight, `WATER_ABSORPTION` and
`WATER_TURBIDITY` shape the body colour, and `WATER_REFRACTION` /
`WATER_REFLECTION` / `WATER_FOAM` turn the individual parts off. Underwater and
in lava, `hzApplyMediaFog` takes over with its own density and colour.

Lava and ice are recognised by their block ids and deliberately skip the water
buffers.

### Sky

`gbuffers_skybasic` draws the whole sky procedurally from the direction of the
sky quad:

* a day/dusk/night gradient with a horizon term,
* a sun disc with glow that reddens towards the horizon,
* a moon disc that follows the actual lunar phase,
* a star field on a rotated grid that fades in at night and out in rain,
* the cloud layer,
* and, when the camera drops below `bedrockLevel`, the darkening that vanilla
  achieves with its black "dark sky" plane.

Vanilla's own sky, sun, moon, stars and clouds are switched off in
`shaders.properties`. Coloured sky quads that vanilla draws with a non zero alpha
(the sunset quad, the End's dark plane) are discarded by the pack, so the
procedural sky is always what you see.

### Clouds

A ray marched layer at `CLOUD_ALTITUDE`, sampled with fBm noise
(`CLOUD_OCTAVES`/`CLOUD_STEPS` from `CLOUD_QUALITY`), drifting with
`CLOUD_SPEED`, covered according to `CLOUD_DENSITY`, lit by the same sun and
ambient terms as the terrain. They are part of the sky, so terrain and entities
occlude them correctly through the depth buffer. `clouds=off` in
`shaders.properties` removes the vanilla cloud plane.

### Fog

`lib/fog.glsl` combines, in this order: vanilla's fog parameters (`fogMode`,
`fogStart`, `fogEnd`, `fogDensity`, `fogShape`) scaled by `FOG_DENSITY`, an
atmospheric term coloured by the sky and brightened towards the sun, extra fog at
the edge of the render distance (`BORDER_FOG`), and a separate media fog for
water and lava with `UNDERWATER_DENSITY`. The Nether and the End get their own
colours and densities through `lib/dimension.glsl`. Iris does not apply vanilla
fog on top of a shader pack, so the pack is responsible for all of it - including
the additive passes (`gbuffers_lightning`, `gbuffers_spidereyes`), which get fog
applied additively so they do not glow through it.

### Post pipeline

| Pass | Writes | Does |
| --- | --- | --- |
| `deferred` | colortex0 | resolves water, applies media fog |
| `composite` | colortex1 | bloom bright pass with a soft knee |
| `composite1` | colortex2 | separable gaussian blur, horizontal |
| `composite2` | colortex1 | separable gaussian blur, vertical |
| `composite3` | colortex2 | second, wider blur, horizontal (`BLOOM_QUALITY >= 1`) |
| `composite4` | colortex1 | second, wider blur, vertical (`BLOOM_QUALITY >= 1`) |
| `composite5` | colortex0, colortex4 | temporal filter: reproject, clamp to the 3x3 neighbourhood, blend (`TEMPORAL_SMOOTHING`) |
| `composite6` | colortex0 | add bloom, tonemap, exposure, saturation, contrast, colour grade |
| `final` | screen | vignette, dithering, gamma / sRGB encode |

* **Bloom** is a two scale gaussian, `BLOOM_THRESHOLD` with a soft knee,
  `BLOOM_STRENGTH` on the way back in.
* **Tonemap** offers Reinhard, ACES and Hable (`TONEMAP_MODE`), then `EXPOSURE`,
  `SATURATION` (luminance preserving) and `CONTRAST`.
* **Colour grading** (`COLOR_GRADING`, off by default) applies a lift/gamma/gain
  tint.
* **Vignette** and **dithering** (a per pixel hash that breaks up banding in the
  sky and fog) run in `final`, followed by the gamma / sRGB encode.
* The bloom passes are removed from the program set entirely when `BLOOM` is off
  (`program.composite.enabled=BLOOM` and friends), and `composite5` the same way
  for `TEMPORAL_SMOOTHING`, so a disabled effect costs nothing.

### Everything else that has to keep working

The pack ships every program Iris needs so that nothing falls back to Iris' own
internal shaders: `gbuffers_basic`, `gbuffers_textured`, `gbuffers_textured_lit`,
`gbuffers_terrain`, `gbuffers_block`, `gbuffers_water`, `gbuffers_entities`,
`gbuffers_lightning`, `gbuffers_hand`, `gbuffers_weather`,
`gbuffers_armor_glint`, `gbuffers_spidereyes`, `gbuffers_skybasic` and `shadow`.

* **Entities** keep their hurt flash (`entityColor`) and their overlay tint, and
  work around Iris' strict translucent entity alpha test so that alpha blended
  entity parts (slimes, ghasts, phantom membranes) are not discarded.
* **The hand** is lit like the world, with `gbuffers_hand_water` falling back to
  it, so a hand in front of water does not punch a hole.
* **Weather** keeps vanilla geometry and gets fog plus a slight darkening from
  the storm.
* **Armour glint** and **spider eyes** stay additive and fullbright.
* `gbuffers_clouds`, `gbuffers_skytextured` and `gbuffers_line` are deliberately
  absent: vanilla clouds and the sky texture are disabled, and Iris falls back to
  `gbuffers_basic` for lines, which is the correct shading for them.

### Dimensions

`world-1/` (Nether) and `world1/` (End) contain **all 23 programs**, because Iris
does not merge a dimension folder with the pack root - a program missing from
`world1/` would silently become Iris' internal fallback, not the Overworld
version. Each wrapper adds `#define DIM_NETHER` or `#define DIM_END` and includes
the same body as the Overworld; `lib/dimension.glsl` switches on it:

| | Overworld | Nether | End |
| --- | --- | --- | --- |
| Sky | gradient, sun, moon, stars, clouds | no sky (fog colour everywhere) | dark sky, stars, no sun or moon |
| Directional light | sun + moon | none | cold "void light" |
| Shadow map | yes | no | yes |
| Clouds | yes | no | no |
| Weather | yes | no | no |
| Fog | atmospheric + border | 2.2x density, dimmed dimension haze | 1.25x density, violet haze |

---

## Settings

Open `Shader Pack Settings`. Three profiles set everything at once; changing any
option by hand switches the profile selector to `Custom`.

| Profile | Shadows | Water | Clouds | Post |
| --- | --- | --- | --- | --- |
| **Low** | off | simple, no refraction/reflection/foam | Low | no bloom, no vignette |
| **Medium** (default) | 2048 px / 128 blocks, soft, coloured | Medium, refraction + reflection + foam | Medium | bloom |
| **High** | 4096 px / 256 blocks, soft, coloured | High (8 wave layers) | High | bloom + temporal filter |

### Lighting
`SUNLIGHT_STRENGTH`, `MOONLIGHT_STRENGTH`, `AMBIENT_STRENGTH`,
`BLOCKLIGHT_STRENGTH`, `BLOCKLIGHT_FALLOFF`, `HAND_LIGHT`, `CAVE_ADAPT`

### Shadows
`SHADOWS`, `SOFT_SHADOWS`, `COLORED_SHADOWS`, `SHADOW_RESOLUTION`,
`SHADOW_DISTANCE`, `SHADOW_SOFTNESS`, `SHADOW_SAMPLES`, `SHADOW_BIAS`,
`SHADOW_DISTORTION`

### Water
`WATER_QUALITY`, `WATER_WAVES`, `WATER_WAVE_STRENGTH`, `WATER_REFRACTION`,
`WATER_REFLECTION`, `WATER_FOAM`, `WATER_ABSORPTION`, `WATER_TURBIDITY`,
`WATER_SHININESS`, `WATER_F0`

### Atmosphere
`FOG_DENSITY`, `UNDERWATER_DENSITY`, `BORDER_FOG`, `STARS`, `STAR_DENSITY`,
`SUN_PATH_TILT`

### Clouds
`CLOUDS`, `CLOUD_QUALITY`, `CLOUD_DENSITY`, `CLOUD_ALTITUDE`, `CLOUD_SPEED`

### Post processing
`BLOOM`, `BLOOM_QUALITY`, `BLOOM_STRENGTH`, `BLOOM_THRESHOLD`, `TONEMAP_MODE`,
`EXPOSURE`, `SATURATION`, `CONTRAST`, `GAMMA`, `VIGNETTE`, `VIGNETTE_STRENGTH`,
`COLOR_GRADING`, `TEMPORAL_SMOOTHING`, `TEMPORAL_STRENGTH`, `DITHERING`

Every option has a label and a tooltip in `shaders/lang/en_us.lang`; numeric
options are sliders, the mode and quality options cycle through labelled values.
All of them live in `shaders/lib/options.glsl`, which is the single place to
change a default.

---

## How the pack is put together

Each program has **one body** in `shaders/programs/<name>.glsl`, written without a
`#version` directive and split into a vertex and a fragment half:

```glsl
#if defined(HZ_STAGE_VERTEX)
void main() { ... }
#endif

#if defined(HZ_STAGE_FRAGMENT)
/* RENDERTARGETS:0 */
void main() { ... }
#endif
```

The six files Iris actually loads - `<name>.vsh`/`.fsh` in the pack root, in
`world-1/` and in `world1/` - are three line wrappers that provide the `#version`,
the stage define, the dimension define and the include:

```glsl
#version 330 compatibility
#define DIM_NETHER
#define HZ_STAGE_FRAGMENT
#include "/programs/gbuffers_water.glsl"
```

They are generated by `tools/generate_programs.py` and must not be edited by
hand. Two rules come straight out of Iris' loader:

* **`#version` appears only in wrappers.** Iris hoists every `#version` line it
  finds to the top of the file, so a body containing one would end up with a
  duplicate directive.
* **Stage and dimension selectors use `#if defined(...)`**, never `#ifdef`. Iris
  registers a `#define NAME` as a user toggleable option when any source
  references it with `#ifdef NAME` or `#ifndef NAME`
  (`OptionAnnotatedSource#parseIfdef`) - a plain `#if` reference is ignored on
  purpose. That is what keeps `HZ_STAGE_VERTEX`, `HZ_STAGE_FRAGMENT`,
  `DIM_NETHER`, `DIM_END` and the include guards out of the settings menu, while
  the real options in `lib/options.glsl` do appear there because they are
  referenced with `#ifdef`/`#ifndef`.

`shaders/lib/` holds the shared code: `options.glsl` (every user option and the
quality presets derived from it), `consts.glsl` (the `const` directives Iris reads
from fragment sources - shadow resolution and distance, sun path rotation,
`colortex` formats, buffer clears), `common.glsl` (uniforms and maths),
`color.glsl`, `dimension.glsl`, `shadow_math.glsl`, `shadows.glsl`,
`lighting.glsl`, `fog.glsl`, `sky.glsl`, `water.glsl`, `material.glsl`,
`buffers.glsl`, `gbuffers_common.glsl`, `composite_common.glsl`, `post.glsl`.

---

## Building and validating

No build step is needed to use the pack - it is plain text. These tools exist so
that changes can be checked without launching Minecraft:

```bash
# regenerate the 138 program wrappers after adding or renaming a program
python3 tools/generate_programs.py

# validate everything (needs a glslang binary)
python3 tools/validate.py
python3 tools/validate.py --glslang /usr/bin/glslangValidator
python3 tools/validate.py --keep-expanded /tmp/expanded   # inspect what glslang saw

# build the archive that goes into shaderpacks/
python3 tools/build_zip.py
python3 tools/build_zip.py --version 1.0.0

# validate without compiling, and check an archive's layout
python3 tools/validate.py --skip-glsl --zip dist/HorizonShaders.zip
```

`tools/validate.py` re-implements the parts of Iris that decide whether a pack
loads, naming the class each rule comes from:

* include expansion (`IncludeProcessor`) - absolute `/lib/...` and relative
  paths, cycle detection, missing files;
* `#version` hoisting (`JcppProcessor` / `GlslCollectingListener`) - exactly one
  directive per program after expansion;
* option discovery and confirmation (`OptionAnnotatedSource`,
  `ShaderPackOptions`) - including the rule that a boolean option is only
  registered when some source references it with `#ifdef`/`#ifndef`, and that a
  valued `#define` without a `//[...]` list is not an option at all;
* option value editing (`OptionAnnotatedSource#edit`), used to compile the pack
  under five different option configurations;
* comment directives (`CommentDirectiveParser`) - `RENDERTARGETS` /
  `DRAWBUFFERS` only in fragment sources, only as digit lists without spaces,
  because Iris calls `Integer.parseInt` on each part;
* const directives (`ConstDirectiveParser`) - collected from fragment sources,
  and texture formats must stay inside comment blocks because `RGBA16F` is not a
  GLSL identifier;
* `shaders.properties` (`ShaderProperties`, `PropertiesPreprocessor`,
  `ProfileSet`, `BooleanParser`) - known keys only, boolean literals where Iris
  expects them, and the two different views of the file (the preprocessed one
  that drives `program.<name>.enabled` and `shadow.enabled`, and the original one
  that drives `sliders`, `screen*` and `profile.*`);
* `block.properties` (`IdMap`, `BlockEntry`) - entry syntax, and every
  `HZ_BLOCK_*` id in `lib/material.glsl` has to have a `block.<id>` entry,
  because shipping the file replaces Iris' legacy id map completely;
* `lang/en_us.lang` (`LanguageMap` and the widget classes) - a label for every
  option, value labels for the mode options, and no key that points at something
  the pack does not have;
* uniforms and samplers (`net.irisshaders.iris.uniforms.*`, `IrisSamplers`) - a
  uniform or sampler Iris does not provide compiles fine and silently reads zero,
  so both are checked against the real lists;
* varyings - every varying a fragment stage declares must be written by its
  vertex stage, which glslang does not flag in the compatibility profile;
* the wrapper generator - the committed wrappers have to match what it produces;
* the archive - `shaders/` must be the only top level entry.

Then every program pair is compiled and linked with
[glslang](https://github.com/KhronosGroup/glslang) (`-l`, which compiles both
stages and validates the interface between them): 23 programs x 3 dimension
folders x 5 option configurations, 207 program pairs in total. The pack is
written in the compatibility dialect Iris accepts as input; Iris' own rewrite
(`attribute`/`varying`, `gl_FragColor`, `texture2D`, ...) is mechanical and is
checked by the lint rules above instead of being simulated.

GitHub Actions (`.github/workflows/validate.yml`) runs the same thing on every
push, pull request and manual dispatch: it installs `glslang-tools`, validates,
builds `dist/HorizonShaders.zip`, re-validates the archive layout and uploads it
as the `HorizonShaders` artifact.

---

## Limitations

These are deliberate, and each one is the closest valid Iris alternative to what
was asked for:

* **Water reflections are environmental, not screen space.** The fresnel term
  reflects the procedural sky (gradient, sun, moon, clouds) and the fog colour.
  Terrain, entities and the player are not reflected: screen space reflections
  would need a colour plus depth history with reprojection, and the artifacts on
  an animated, half transparent surface are worse than the missing reflection.
* **Refraction cannot show occluded geometry.** It offsets into the scene colour
  and depth that already exist (`depthtex1`), so it bends what is visible rather
  than revealing what the surface hides. Samples that cross the water surface are
  rejected, which is why a hand or a rain streak over water does not smear into
  the lake bed.
* **The temporal filter is anti flicker, not TAA.** Iris exposes no sub pixel
  projection jitter, so there is no new information to reconstruct and no
  sharpening step. It removes shimmer on thin geometry, wave crests and shadow
  edges; fast motion can ghost for a frame or two despite the neighbourhood
  clamp and depth rejection.
* **One orthographic shadow map, no cascades.** Resolution and distance are a
  single trade off (`SHADOW_RESOLUTION` / `SHADOW_DISTANCE`), shadows fade out
  before the edge, and there is nothing beyond it.
* **No PBR.** The pack does not read `_n` / `_s` / `_e` texture maps; surface
  response is analytic and emissive blocks come from `block.properties`.
* **No voxelisation, no compute.** That means no global illumination, no
  path traced shadows and no volumetric light shafts; the sun glow and the
  atmospheric fog are analytic.
* **Clouds do not cast shadows.** They live in the sky program, so they occlude
  and are occluded correctly through the depth buffer, but there is no cloud
  shadow term on the ground.
* **The sky is fully procedural.** No vanilla sky texture, no custom skybox, no
  aurora; sunrise and sunset colours come from the sun height.
* **The Nether has no directional light and no shadow map**, matching the fact
  that it has no sky. It is lit by ambient and block light only.
* **Distant Horizons is not supported.** No `dh*` programs and no
  `dhShadow.enabled`.
* **Not tested under OptiFine.** The pack only uses conventions that the Iris
  source for 1.21.1 implements, but it is written and validated for Iris.

### Validation status

The pack passes every check in `tools/validate.py`, including compiling and
linking all 207 program pairs. What this repository cannot do is run Minecraft:
the visual result has not been verified in game, so treat the first launch as the
remaining test. If something looks wrong, the log Iris writes
(`logs/latest.log`, plus the `Shader Pack Settings -> Shader Pack Errors` screen)
will name the program, and the validator reproduces the same errors offline.

---

## Repository layout

```
HorizonShaders/shaders/           the pack itself
    programs/*.glsl               23 program bodies (no #version)
    lib/*.glsl                    16 shared libraries
    *.vsh, *.fsh                  46 Overworld wrappers   (generated)
    world-1/, world1/             92 dimension wrappers    (generated)
    shaders.properties            pack properties
    block.properties              block material ids
    lang/en_us.lang               menu strings
tools/generate_programs.py        writes the wrappers from the bodies
tools/validate.py                 the offline Iris loader + glslang harness
tools/build_zip.py                packages dist/HorizonShaders.zip
.github/workflows/validate.yml    CI: validate, package, upload
```
