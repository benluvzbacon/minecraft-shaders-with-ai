//==============================================================================
//
//   Horizon Shaders  -  gbuffers_hand
//
//   The first person hand and the item held in it: HAND_CUTOUT (lightmap),
//   HAND_CUTOUT_BRIGHT (fullbright), HAND_CUTOUT_DIFFUSE and HAND_TEXT /
//   HAND_TEXT_INTENSITY (the glyph format, used for text on held books and
//   maps). HAND_TRANSLUCENT and HAND_WATER_* fall back here through
//   ProgramId.HandWater -> Hand.
//
//   The hand pass uses its own projection matrix, but the model view rotation is
//   unchanged, so the view space position handed to the lighting model is still
//   the real one and shadows, fog and the held item light all work. The hand is
//   drawn after the world, so it also gets the underwater tint from the media
//   fog applied in deferred.
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

	// The hand uses a vertex format with an overlay coordinate, so entityColor
	// arrives as the overlay tint (the hurt flash of the held entity/item).
	albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);

	vec3 colour = hzShadeSurface(albedo.rgb, hzNormal, hzViewPos, hzPlayerPos,
	                             hzLmCoord, 0.0);

	gl_FragColor = vec4(colour, textureColour.a);
}

#endif // HZ_STAGE_FRAGMENT
