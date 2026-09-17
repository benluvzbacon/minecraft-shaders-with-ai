//==============================================================================
//
//   Horizon Shaders  -  gbuffers_armor_glint
//
//   The enchantment glint overlay. GLINT is POSITION_TEX with a NON_ZERO alpha
//   test; because the format has no colour attribute, Iris routes the glint
//   strength through the colour modulator: gl_Color becomes
//   vec4(iris_ColorModulator.rgb, iris_ColorModulator.a * iris_GlintAlpha).
//   That is why the alpha written here is the texture alpha times the vertex
//   alpha - it carries the fade in/out of the glint.
//
//   Glint is drawn with vanilla's own blend state, which brightens what is under
//   it, so the fog scales the colour instead of mixing towards the fog colour
//   (mixing would make a distant glint glow like a light source).
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
	vec4 textureColour = texture2D(gtexture, hzTexCoord);

	vec3 albedo = hzSrgbToLinear(textureColour.rgb * hzVertexColour.rgb);
	vec3 colour = albedo * (hzFullbrightLighting() * 1.35);
	colour = hzApplyFogAdditive(colour, hzViewPos);

	// NON_ZERO alpha test: Iris discards anything at or below 0.0001.
	gl_FragColor = vec4(colour, textureColour.a * hzVertexColour.a);
}

#endif // HZ_STAGE_FRAGMENT
