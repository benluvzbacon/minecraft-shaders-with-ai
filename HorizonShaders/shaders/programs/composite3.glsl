//==============================================================================
//
//   Horizon Shaders  -  composite3
//
//   Bloom, step 4: horizontal half of the second, wider blur iteration
//   (colortex1 -> colortex2). A second pass at roughly 2.6 times the radius is
//   what turns the tight glow into a bloom that reads over a whole bright area.
//   On the lowest bloom quality the two wide passes are skipped and the buffer is
//   passed through untouched, which keeps the ping pong parity so that the narrow
//   result still ends up in colortex1.
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

#if BLOOM_WIDE
	vec3 colour = hzBlurGaussian(colortex1, hzUv, vec2(texel.x * BLOOM_RADIUS * 2.6, 0.0));
#else
	vec3 colour = texture2D(colortex1, hzUv).rgb;
#endif

	gl_FragColor = vec4(colour, 1.0);
}

#endif // HZ_STAGE_FRAGMENT
