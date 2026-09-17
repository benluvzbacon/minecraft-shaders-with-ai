//==============================================================================
//
//   Horizon Shaders  -  final
//
//   Last pass: the display encoding. The vignette is applied in linear light
//   before the sRGB curve so that it darkens the way a real lens vignette does,
//   then the curve, then an ordered-ish dither that breaks up banding in the sky,
//   the fog and the water.
//
//   The final pass always renders to the main framebuffer, so it carries no
//   RENDERTARGETS directive; colortex0 is bound here as the default sampler.
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

void main() {
	vec3 colour = hzSceneColour(hzUv);

	colour = hzDisplayEncode(colour, hzUv, gl_FragCoord.xy);

	gl_FragColor = vec4(colour, 1.0);
}

#endif // HZ_STAGE_FRAGMENT
