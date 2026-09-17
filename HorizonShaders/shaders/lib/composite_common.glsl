//==============================================================================
//
//   Horizon Shaders  -  shared code for the fullscreen post processing stages
//
//   deferred, composite* and final are all fullscreen passes. Iris draws them as
//   a quad that already covers the screen, so the canonical OptiFine/Iris vertex
//   shader is enough:
//
//       gl_Position = ftransform();
//       uv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
//
//   Both of those legacy built-ins are rewritten by Iris' CompositeTransformer,
//   which is why every post stage in this pack is written the same way.
//
//==============================================================================

#if !defined(HZ_COMPOSITE_COMMON_GLSL)
#define HZ_COMPOSITE_COMMON_GLSL

#include "/lib/common.glsl"
#include "/lib/color.glsl"
#include "/lib/buffers.glsl"
#include "/lib/consts.glsl"

varying vec2 hzUv;

vec2 hzTexel() {
	return vec2(1.0 / viewWidth, 1.0 / viewHeight);
}

#if defined(HZ_STAGE_VERTEX)

void hzCompositeVertex() {
	gl_Position = ftransform();
	hzUv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}

#endif

#if defined(HZ_STAGE_FRAGMENT)

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

float hzSceneDepth(vec2 uv) {
	return texture2D(depthtex0, uv).r;
}

// True for pixels that did not hit any geometry (the sky, or the void).
bool hzIsSky(float depth) {
	return depth >= 1.0;
}

vec3 hzSceneColour(vec2 uv) {
	return texture2D(colortex0, uv).rgb;
}

#endif

#endif // HZ_COMPOSITE_COMMON_GLSL
