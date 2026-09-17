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
