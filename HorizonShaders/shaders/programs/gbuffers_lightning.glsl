//==============================================================================
//
//   Horizon Shaders  -  gbuffers_lightning
//
//   Lightning bolts. ShaderKey.LIGHTNING is POSITION_COLOR with FULLBRIGHT
//   lighting and no alpha test, and vanilla blends bolts additively
//   (SRC_ALPHA, ONE) - so the fog has to scale the colour down instead of mixing
//   it towards the fog colour, which would make the bolt glow like a lamp.
//
//   There is no texture and no lightmap here: a bolt is pure vertex colour, and
//   the shadow map is skipped because a one pixel wide quad inside a percentage
//   closer filter only produces flicker.
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

void main() {
	vec4 vertexColour = hzVertexColour;
	vec3 albedo = hzSrgbToLinear(vertexColour.rgb);

	// Well above the bloom threshold, which is what gives the bolt its glow.
	vec3 colour = albedo * (hzFullbrightLighting() * 2.2);
	colour = hzApplyFogAdditive(colour, hzViewPos);

	gl_FragColor = vec4(colour, vertexColour.a);
}

#endif // HZ_STAGE_FRAGMENT
