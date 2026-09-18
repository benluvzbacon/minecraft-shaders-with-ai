//==============================================================================
//
//   Horizon Shaders  -  gbuffers_weather
//
//   Rain and snow. WEATHER uses the particle vertex format (position, uv0,
//   colour, lightmap) with a ONE_TENTH alpha test and lightmap lighting.
//
//   Precipitation is thin, fast moving geometry that covers a lot of screen
//   space, so it is shaded with the flat variant of the lighting model: lightmap
//   ambient, block light and an unshadowed directional term, but no shadow map
//   lookup. Sampling a percentage closer filter for a one pixel wide streak only
//   produces flicker.
//
//==============================================================================

#include "/lib/gbuffers_common.glsl"
#include "/lib/lighting.glsl"

#if defined(HZ_STAGE_VERTEX)

void main() {
	hzVertexCommon();
}

#endif // HZ_STAGE_VERTEX

#if defined(HZ_STAGE_FRAGMENT)

uniform sampler2D gtexture;

void main() {
	vec4 textureColour = texture2D(gtexture, hzTexCoord) * hzVertexColour;
	vec4 albedo = hzAlbedoFromTexture(textureColour);

	vec3 colour = hzShadeFlat(albedo.rgb, hzNormal, hzViewPos, hzPlayerPos,
	                          hzLmCoord);

	gl_FragColor = vec4(colour, textureColour.a);
}

#endif // HZ_STAGE_FRAGMENT
