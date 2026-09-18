//==============================================================================
//
//   Horizon Shaders  -  composite1
//
//   Bloom, step 2: horizontal half of the first separable gaussian blur,
//   colortex1 -> colortex2. Five linear filtered taps reproduce the classic
//   1 4 6 4 1 / 16 kernel.
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

/* RENDERTARGETS:2 */

void main() {
	vec2 texel = hzTexel();

	vec3 colour = hzBlurGaussian(colortex1, hzUv, vec2(texel.x * BLOOM_RADIUS, 0.0));

	gl_FragColor = vec4(colour, 1.0);
}

#endif // HZ_STAGE_FRAGMENT
