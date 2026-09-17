//==============================================================================
//
//   Horizon Shaders  -  pack level const directives
//
//   Iris collects "const option" directives from the *fragment* source of every
//   gbuffers, deferred, composite, begin and prepare program
//   (net.irisshaders.iris.shaderpack.programs.ProgramSet#locateDirectives),
//   after #include expansion and preprocessing. That is why this file is
//   included from lib/gbuffers_common.glsl and from the post processing stages:
//   no matter which program Iris happens to look at first, it finds the same
//   values.
//
//   Two kinds of directive live here:
//     - real GLSL const declarations (numbers and bools). The preprocessor has
//       already substituted the option macros, so Iris sees a plain literal.
//     - texture format directives. Their values (RGBA16F, ...) are *not* valid
//       GLSL identifiers, so by long standing OptiFine/Iris convention they are
//       written inside a comment block, which Iris' directive parser still reads
//       line by line.
//
//==============================================================================

#if !defined(HZ_CONSTS_GLSL)
#define HZ_CONSTS_GLSL

#include "/lib/options.glsl"

//---------------------------------- shadows -----------------------------------

const int shadowMapResolution = SHADOW_RESOLUTION;
const float shadowDistance = SHADOW_DISTANCE;
const float sunPathRotation = SUN_PATH_TILT;

// The pack does its own percentage closer filtering, so the driver's hardware
// compare sampler stays off and shadowtex0/1 give plain depth values.
const bool shadowHardwareFiltering = false;
const bool shadowtex0Mipmap = false;
const bool shadowtex1Mipmap = false;
const bool shadowcolor0Mipmap = false;

//-------------------------------- render targets -------------------------------

/*
const int colortex0Format = RGBA16F;
const int colortex1Format = RGBA16F;
const int colortex2Format = RGBA16F;
const int colortex3Format = RGBA16F;
const int colortex4Format = RGBA16F;
*/

// colortex4 holds the previous frame for the temporal filter, so it must not be
// cleared between frames. Every other buffer is cleared (the Iris default).
const bool colortex4Clear = false;

#endif // HZ_CONSTS_GLSL
