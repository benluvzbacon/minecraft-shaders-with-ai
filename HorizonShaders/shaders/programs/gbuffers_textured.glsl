//==============================================================================
//
//   Horizon Shaders  -  gbuffers_textured
//
//   Textured geometry with no lightmap: beacon beams, and (through Iris'
//   fallback chain) anything that would otherwise use gbuffers_skytextured or
//   gbuffers_clouds. This pack disables the vanilla sun, moon, stars and cloud
//   layer in shaders.properties and draws its own atmosphere in
//   gbuffers_skybasic, so in practice the beacon beam is what ends up here.
//
//   Render types that land here:
//     TEXTURED        POSITION_TEX        alpha test "not zero"
//     TEXTURED_COLOR  POSITION_TEX_COLOR  alpha test "one tenth"
//     BEACON          BLOCK               fullbright, alpha test off
//   All of them are unlit by design (BEACON is explicitly FULLBRIGHT), so the
//   surface is only tinted by fog. Formats without a lightmap get
//   gl_MultiTexCoord1 replaced with vec4(240.0, 240.0, 0.0, 1.0) by Iris, which
//   is why this program deliberately does not use the lightmap at all.
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

	vec3 colour = hzShadeFullbright(albedo.rgb, hzViewPos, hzPlayerPos, 1.0);

	gl_FragColor = vec4(colour, textureColour.a);
}

#endif // HZ_STAGE_FRAGMENT
