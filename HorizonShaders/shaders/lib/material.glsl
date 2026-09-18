//==============================================================================
//
//   Horizon Shaders  -  block material ids
//
//   Iris fills the mc_Entity vertex attribute from the pack's block.properties
//   (or from its built in legacy map when the pack does not ship one). This pack
//   ships block.properties, which replaces the legacy map entirely, so every id
//   used below is declared there.
//
//   -1 means "no id", which is what every non terrain render type gets.
//
//==============================================================================

#if !defined(HZ_MATERIAL_GLSL)
#define HZ_MATERIAL_GLSL

#include "/lib/common.glsl"

#define HZ_BLOCK_NONE       -1.0
#define HZ_BLOCK_WATER       9.0
#define HZ_BLOCK_LAVA       11.0
#define HZ_BLOCK_ICE        79.0
#define HZ_BLOCK_MOLTEN    100.0
#define HZ_BLOCK_LAMP      101.0
#define HZ_BLOCK_FLAME     102.0
#define HZ_BLOCK_FOLIAGE   200.0

bool hzIsWater(float blockId) {
	return blockId == HZ_BLOCK_WATER;
}

bool hzIsLava(float blockId) {
	return blockId == HZ_BLOCK_LAVA;
}

bool hzIsIce(float blockId) {
	return blockId == HZ_BLOCK_ICE;
}

// Self illumination strength, added on top of the lightmap based lighting so
// that light sources read as bright even when the lightmap is saturated.
bool hzIsFoliage(float blockId) {
	return blockId == HZ_BLOCK_FOLIAGE;
}

// Wind sway for leaves, grasses and crops. Shared by the terrain and the
// shadow pass so a swaying canopy keeps its shadow attached. worldPos is
// the camera relative world position of the vertex - in both passes chunk
// geometry arrives unrotated, so gl_Vertex.xyz + cameraPosition is it.
vec3 hzFoliageSway(vec3 worldPos, float blockId) {
#ifndef WAVING_FOLIAGE
	return vec3(0.0);
#endif
	if (!hzIsFoliage(blockId)) {
		return vec3(0.0);
	}

	float phase = dot(worldPos.xz, vec2(0.83, 0.61));
	float gust = sin(frameTimeCounter * 1.6 + phase)
		+ 0.5 * sin(frameTimeCounter * 2.7 + phase * 1.7 + worldPos.y * 0.35);

	// Tops of plants travel further than their roots; on leaf blocks the
	// same fraction gives a gentle shear across the canopy.
	float weight = 0.045 * (0.30 + 0.70 * fract(worldPos.y + 0.001));

	return vec3(gust * weight, 0.0, gust * weight * 0.7);
}

float hzEmissive(float blockId) {
	if (blockId == HZ_BLOCK_LAVA) {
		return 2.4;
	}
	if (blockId == HZ_BLOCK_MOLTEN) {
		return 2.4;
	}
	if (blockId == HZ_BLOCK_LAMP) {
		return 1.15;
	}
	if (blockId == HZ_BLOCK_FLAME) {
		return 0.85;
	}

	return 0.0;
}

#endif // HZ_MATERIAL_GLSL
