//==============================================================================
//
//   Horizon Shaders  -  composite4
//
//   Bloom, step 5: vertical half of the second, wider blur iteration,
//   colortex2 -> colortex1. After this pass colortex1 holds the finished bloom.
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

#if BLOOM_WIDE
	vec3 colour = hzBlurGaussian(colortex2, hzUv, vec2(0.0, texel.y * BLOOM_RADIUS * 2.6));
#else
	vec3 colour = texture2D(colortex2, hzUv).rgb;
#endif

	gl_FragColor = vec4(colour, 1.0);
}

#endif // HZ_STAGE_FRAGMENT
