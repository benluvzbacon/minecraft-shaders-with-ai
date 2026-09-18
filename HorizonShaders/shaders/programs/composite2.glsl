//==============================================================================
//
//   Horizon Shaders  -  composite2
//
//   Bloom, step 3: vertical half of the first separable gaussian blur,
//   colortex2 -> colortex1.
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
	vec2 texel = hzTexel();

	vec3 colour = hzBlurGaussian(colortex2, hzUv, vec2(0.0, texel.y * BLOOM_RADIUS));

	gl_FragColor = vec4(colour, 1.0);
}

#endif // HZ_STAGE_FRAGMENT
