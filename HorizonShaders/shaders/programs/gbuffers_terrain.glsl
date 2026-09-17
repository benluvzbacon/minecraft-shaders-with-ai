//==============================================================================
//
//   Horizon Shaders  -  gbuffers_terrain
//
//   The workhorse program: solid, cutout and cutout mipped terrain
//   (TERRAIN_SOLID, TERRAIN_CUTOUT -> Terrain), the block breaking overlay
//   (CRUMBLING -> DamagedBlock -> Terrain) and, through the fallback chain,
//   anything that only names gbuffers_terrain_solid / _cutout.
//
//   This is also the program that reads the block material id. Iris fills the
//   mc_Entity attribute from the pack's block.properties: for Sodium terrain
//   SodiumTransformer#replaceMCEntity rewrites the declaration into the decoded
//   id (int(raw >> 1) - 1), for vanilla terrain the attribute is bound directly.
//   Blocks that are not listed get -1.
//
//   Leaves are the reason the alpha written here has to be the real one: Iris
//   appends ONE_TENTH_ALPHA for TERRAIN_CUTOUT, which is what keeps the gaps in
//   leaf and cutout textures empty.
//
//==============================================================================

#include "/lib/gbuffers_common.glsl"
#include "/lib/lighting.glsl"
#include "/lib/material.glsl"

#if defined(HZ_STAGE_VERTEX)

attribute vec4 mc_Entity;

void main() {
	hzVertexCommon();

	hzBlockId = mc_Entity.x;
}

#endif // HZ_STAGE_VERTEX

#if defined(HZ_STAGE_FRAGMENT)

uniform sampler2D gtexture;

void main() {
	// Vanilla hands over the biome tint and the baked ambient occlusion already
	// multiplied into the vertex colour (separateAo is off in shaders.properties).
	vec4 textureColour = texture2D(gtexture, hzTexCoord) * hzVertexColour;
	vec4 albedo = hzAlbedoFromTexture(textureColour);

	// Lava, torches, lamps and the like light themselves on top of the lightmap.
	float emissive = hzEmissive(hzBlockId);

	vec3 colour = hzShadeSurface(albedo.rgb, hzNormal, hzViewPos, hzPlayerPos,
	                             hzLmCoord, emissive);

	gl_FragColor = vec4(colour, textureColour.a);
}

#endif // HZ_STAGE_FRAGMENT
