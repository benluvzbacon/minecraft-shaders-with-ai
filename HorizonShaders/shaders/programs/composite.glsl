//==============================================================================
//
//   Horizon Shaders  -  composite
//
//   Bloom, step 1: the bright pass. Everything in the HDR scene above the
//   threshold is copied into colortex1, which the following four passes blur.
//   A soft knee is used instead of a hard cutoff so that surfaces do not pop in
//   and out of the bloom as the exposure changes.
//
//   The whole bloom chain is switched off through shaders.properties
//   (program.composite*.enabled=BLOOM) when the option is disabled; the #ifdef
//   below keeps the output correct if the passes are ever run anyway.
//
//==============================================================================

#include "/lib/composite_common.glsl"
#include "/lib/post.glsl"

#if defined(HZ_STAGE_VERTEX)

void main() {
	hzCompositeVertex();
}

#endif // HZ_STAGE_VERTEX

#if defined(HZ_STAGE_FRAGMENT)

/* RENDERTARGETS:1 */

void main() {
#ifdef BLOOM
	vec3 bright = hzBrightPass(hzSceneColour(hzUv));
#else
	vec3 bright = vec3(0.0);
#endif

	gl_FragColor = vec4(bright, 1.0);
}

#endif // HZ_STAGE_FRAGMENT
