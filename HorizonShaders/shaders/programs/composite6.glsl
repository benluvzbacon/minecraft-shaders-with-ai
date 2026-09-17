//==============================================================================
//
//   Horizon Shaders  -  composite6
//
//   The resolve pass: bloom is added to the HDR scene, the result is exposure
//   scaled, tone mapped, graded and clamped. What lands in colortex0 from here on
//   is display referred LDR; final only encodes it.
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

/* RENDERTARGETS:0 */

void main() {
	vec3 colour = hzSceneColour(hzUv);

	vec3 bloom = vec3(0.0);

#ifdef BLOOM
	bloom = texture2D(colortex1, hzUv).rgb;
#endif

	colour = hzTonemapChain(colour, bloom);

	gl_FragColor = vec4(colour, 1.0);
}

#endif // HZ_STAGE_FRAGMENT
