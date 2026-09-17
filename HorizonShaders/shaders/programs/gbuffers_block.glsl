//==============================================================================
//
//   Horizon Shaders  -  gbuffers_block
//
//   Block entities (chests, signs, banners, shulker boxes, beds, ...) and piston
//   moved blocks: BLOCK_ENTITY / BE_TRANSLUCENT / MOVING_BLOCK / IE_COMPAT all
//   resolve to ProgramId.Block.
//
//   It is shaded exactly like terrain, but it deliberately does *not* read
//   mc_Entity. Block entities are rendered with IrisVertexFormats.ENTITY, whose
//   attribute slot 11 holds iris_Entity - the *entity* id from entity.properties
//   - and not the block material id. Reading it as a block id would make random
//   chests and signs glow, so the emissive lookup stays in gbuffers_terrain.
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

	// ONE_TENTH alpha test for block entities, so keep the real alpha.
	gl_FragColor = vec4(colour, textureColour.a);
}

#endif // HZ_STAGE_FRAGMENT
