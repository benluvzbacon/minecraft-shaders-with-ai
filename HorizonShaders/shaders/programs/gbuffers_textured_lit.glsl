//==============================================================================
//
//   Horizon Shaders  -  gbuffers_textured_lit
//
//   Textured geometry that carries a lightmap but is not terrain: dropped items,
//   item frames, and - through Iris' fallback chain - particles
//   (PARTICLES / PARTICLES_TRANS -> TexturedLit).
//
//   The particle format has no normal attribute, so Iris replaces gl_Normal with
//   vec3(0.0, 0.0, 1.0): a camera facing normal. Billboards therefore all
//   receive the same directional term, which reads as flat, evenly lit sprites -
//   exactly how vanilla lights them.
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

	vec3 colour = hzShadeSurface(albedo.rgb, hzNormal, hzViewPos, hzPlayerPos,
	                             hzLmCoord, 0.0);

	// ONE_TENTH alpha test for particles and item-like render types: the value
	// written here is what Iris compares against 0.1.
	gl_FragColor = vec4(colour, textureColour.a);
}

#endif // HZ_STAGE_FRAGMENT
