//==============================================================================
//
//   Horizon Shaders  -  gbuffers_spidereyes
//
//   Emissive entity overlays: SPS (spider and enderman eyes, POSITION_TEX_COLOR,
//   fullbright, no alpha test) and ENTITIES_EYES / ENTITIES_EYES_TRANS (the
//   entity vertex format, fullbright, NON_ZERO / ONE_TENTH alpha test).
//
//   ProgramId.SpiderEyes carries an explicit blend override of
//   (SRC_ALPHA, ONE, ZERO, ONE), i.e. the overlay is added to whatever is under
//   it. Two consequences: the lightmap must not be used (fullbright means the
//   eyes keep glowing in a dark cave, which is the whole point), and the fog has
//   to scale the colour down instead of mixing towards the fog colour.
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

	vec3 albedo = hzSrgbToLinear(textureColour.rgb);
	vec3 colour = albedo * (hzFullbrightLighting() * 1.7);
	colour = hzApplyFogAdditive(colour, hzViewPos);

	gl_FragColor = vec4(colour, textureColour.a);
}

#endif // HZ_STAGE_FRAGMENT
