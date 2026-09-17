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
// material.glsl is needed in the vertex stage as well for the foliage sway;
// its include guard keeps the fragment stage from seeing it twice.

#if defined(HZ_STAGE_VERTEX)

attribute vec4 mc_Entity;

void main() {
	// Sway foliage before the common transform, so lighting, fog and the
	// shadow map all see the moved vertex. gl_Vertex is read only, hence
	// the local copy.
	vec4 vertex = gl_Vertex;
	vertex.xyz += hzFoliageSway(vertex.xyz + cameraPosition, mc_Entity.x);

	hzVertexCommon(vertex);

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

	// Foliage gets per-texel normal detail: a canopy shaded with one flat
	// normal per face reads as green cardboard, and this is the difference
	// between that and thousands of individual leaves.
	float foliage = float(hzIsFoliage(hzBlockId));
	vec3 normal = hzNormal;
	if (foliage > 0.5) {
		vec2 texel = floor(hzTexCoord * 96.0);
		normal = normalize(normal + (vec3(
			hzHash21(texel),
			hzHash21(texel + 19.19),
			hzHash21(texel + 41.70)) - 0.5) * 0.9);
	}

	// Lava, torches, lamps and the like light themselves on top of the lightmap.
	float emissive = hzEmissive(hzBlockId);

	vec3 colour = hzShadeSurface(albedo.rgb, normal, hzViewPos, hzPlayerPos,
	                             hzLmCoord, emissive);

	// Backlit translucency: sun or moon straight through a leaf glows warm,
	// scaled by sky light so it never happens inside a cave.
	float backlight = pow(clamp(dot(normalize(hzViewPos), hzLightDir()), 0.0, 1.0), 3.0);
	colour += albedo.rgb * vec3(1.00, 0.78, 0.42) * backlight * foliage
		* hzSkyLightCurve(hzLmCoord.y) * 0.55;

	gl_FragColor = vec4(colour, textureColour.a);
}

#endif // HZ_STAGE_FRAGMENT
