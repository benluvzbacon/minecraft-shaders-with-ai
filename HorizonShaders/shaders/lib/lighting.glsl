//==============================================================================
//
//   Horizon Shaders  -  lighting model (fragment stages only)
//
//   Everything is evaluated in linear light. The result of hzLighting() is a
//   multiplier for the surface albedo, made of:
//     - direct sun / moon light, shadow mapped
//     - hemisphere sky ambient driven by the vanilla sky lightmap
//     - warm block light driven by the vanilla block lightmap
//     - dynamic light from the item held in the player hands
//     - vanilla "brightness" / night vision / blindness behaviour
//
//==============================================================================

#if !defined(HZ_LIGHTING_GLSL)
#define HZ_LIGHTING_GLSL

#include "/lib/dimension.glsl"
#include "/lib/shadows.glsl"
#include "/lib/sky.glsl"
#include "/lib/fog.glsl"

// lmCoord arrives as a lightmap texture coordinate in [1/32, 31/32]; this maps
// it onto the vanilla 0..15 light level range.
vec2 hzLightLevels(vec2 lmCoord) {
	return clamp((lmCoord - 0.03125) * (16.0 / 15.0), vec2(0.0), vec2(1.0));
}

// S shaped curve, keeps the outdoors bright and makes the last light levels
// before a cave falls off smoothly instead of linearly.
float hzSkyLightCurve(float level) {
	return level * level * (3.0 - 2.0 * level);
}

float hzBlockLightCurve(float level) {
	float curved = pow(level, BLOCKLIGHT_FALLOFF);

	// A faint linear tail so that a single far away torch is still visible.
	return curved + level * 0.015;
}

vec3 hzBlockLightColour() {
	return vec3(1.00, 0.58, 0.26) * 1.45;
}

// Minimum light level so that fully dark areas are never crushed to pure black.
// Honours the vanilla brightness slider, night vision and blindness.
float hzAmbientFloor() {
	float floorLight = 0.010 + screenBrightness * 0.055;

#ifdef CAVE_ADAPT
	// When the camera itself is in the dark, lift the floor a little so that
	// caves stay readable, the way vanilla's own lightmap does.
	float eyeSky = float(eyeBrightnessSmooth.y) / 240.0;
	floorLight += 0.020 * (1.0 - smoothstep(0.0, 0.45, eyeSky));
#endif

	return floorLight;
}

//------------------------------------------------------------------------------
// Main entry point.
//   playerPos  : camera relative world position of the shaded fragment
//   viewNormal : normal in view space (normalised)
//   lmCoord    : lightmap coordinate from the vertex shader
//------------------------------------------------------------------------------
vec3 hzLighting(vec3 playerPos, vec3 viewNormal, vec2 lmCoord) {
	vec3 normal = normalize(viewNormal);
	vec2 lightLevel = hzLightLevels(lmCoord);

	float skyLight = hzSkyLightCurve(lightLevel.y);
	float blockLight = hzBlockLightCurve(lightLevel.x);

	//----------------------------- direct light -------------------------------
	vec3 direct = vec3(0.0);

#if HZ_HAS_SHADOWS || HZ_HAS_SUN || HZ_DIM_ID == 2
	// Soften the terminator a little, a hard NdotL cutoff looks wrong on the
	// blocky geometry Minecraft gives us.
	const float wrap = 0.12;
	float ndl = clamp((dot(normal, hzLightDir()) + wrap) / (1.0 + wrap), 0.0, 1.0);

	vec3 shadow = hzShadowAt(playerPos, normal);

	// The cloud deck darkens the sun the same way the shadow map darkens a
	// wall: hzCloudShadow samples the coverage field where the light ray
	// enters the cloud base, so the shadows on the ground always match the
	// clouds overhead.
	direct = hzDirectLight() * ndl * shadow * hzCloudShadow(hzWorldPos(playerPos));
#endif

	//----------------------------- sky ambient --------------------------------
	float hemisphere = dot(normal, hzUpDir()) * 0.5 + 0.5;
	vec3 ambientColour = mix(hzGroundColour(), hzAmbientColour(), hemisphere);

	vec3 ambient = ambientColour * skyLight;

	// Skylight leaking in from the sides, keeps caves and interiors from being
	// lit by nothing at all when the player is standing in daylight.
	float eyeSky = float(eyeBrightnessSmooth.y) / 240.0;
	ambient += hzAmbientColour() * (eyeSky * 0.10) * (1.0 - skyLight);

	//----------------------------- block light --------------------------------
	vec3 blockContrib = hzBlockLightColour() * (blockLight * BLOCKLIGHT_STRENGTH);

	//------------------------------- held light -------------------------------
#ifdef HAND_LIGHT
	{
		int mainHand = heldBlockLightValue;
		int offHand = heldBlockLightValue2;
		float heldLevel = float(max(mainHand, offHand)) / 15.0;

		if (heldLevel > 0.0) {
			vec3 heldColour = mainHand >= offHand ? heldBlockLightColor : heldBlockLightColor2;
			float distance = length(playerPos);
			float attenuation = hzBlockLightCurve(heldLevel) / (1.0 + distance * distance * 0.22);
			blockContrib += heldColour * (attenuation * 1.6 * BLOCKLIGHT_STRENGTH);
		}
	}
#endif

	//-------------------------------- combine ---------------------------------
	vec3 lighting = direct * skyLight + ambient + blockContrib;

	// Never fully black: vanilla always keeps a minimum light level.
	lighting += vec3(hzAmbientFloor());

	//-------------------------------- effects ---------------------------------
	lighting *= 1.0 + nightVision * 2.2;
	lighting += vec3(0.30, 0.33, 0.28) * nightVision;
	lighting *= mix(1.0, 0.02, blindness);

	return lighting;
}

// Unlit / fullbright variant used by glowing things (spider eyes, glint, ...).
vec3 hzFullbrightLighting() {
	return vec3(1.0 + nightVision * 2.2) * mix(1.0, 0.02, blindness);
}

//------------------------------------------------------------------------------
// Cheaper variant for thin geometry that must not sample the shadow map: rain,
// snow and lightning bolts. They are lit by the lightmap, the sky ambient and an
// unshadowed directional term, which is both faster and free of the artefacts a
// one pixel wide bolt would produce inside a percentage closer filter.
//------------------------------------------------------------------------------
vec3 hzLightingFlat(vec3 viewNormal, vec2 lmCoord) {
	vec3 normal = normalize(viewNormal);
	vec2 lightLevel = hzLightLevels(lmCoord);

	float skyLight = hzSkyLightCurve(lightLevel.y);
	float blockLight = hzBlockLightCurve(lightLevel.x);

	float hemisphere = dot(normal, hzUpDir()) * 0.5 + 0.5;
	vec3 ambient = mix(hzGroundColour(), hzAmbientColour(), hemisphere) * skyLight;

	vec3 lighting = ambient + hzBlockLightColour() * (blockLight * BLOCKLIGHT_STRENGTH);

#if HZ_HAS_SUN || HZ_DIM_ID == 2
	const float wrap = 0.12;
	float ndl = clamp((dot(normal, hzLightDir()) + wrap) / (1.0 + wrap), 0.0, 1.0);
	lighting += hzDirectLight() * (ndl * skyLight);
#endif

	lighting += vec3(hzAmbientFloor());
	lighting *= 1.0 + nightVision * 2.2;
	lighting *= mix(1.0, 0.02, blindness);

	return lighting;
}

vec3 hzShadeFlat(vec3 albedo, vec3 viewNormal, vec3 viewPos, vec3 playerPos, vec2 lmCoord) {
	vec3 colour = albedo * hzLightingFlat(viewNormal, lmCoord);
	return hzApplyFog(colour, viewPos, playerPos);
}

//------------------------------------------------------------------------------
// Lighting for a surface whose lightmap is not available where it is shaded.
// The water resolve in deferred only knows the sky light level that
// gbuffers_water stored in the water buffer; block light is deliberately left
// out, because the light reaching the eye through the refracted background
// already carries it.
//------------------------------------------------------------------------------
vec3 hzLightingSkyOnly(vec3 playerPos, vec3 viewNormal, float skyLightLevel,
                       out vec3 shadowOut) {
	vec3 normal = normalize(viewNormal);
	float skyLight = hzSkyLightCurve(skyLightLevel);

	vec3 lighting = vec3(0.0);
	vec3 shadow = vec3(1.0);

#if HZ_HAS_SUN || HZ_DIM_ID == 2
	const float wrap = 0.12;
	float ndl = clamp((dot(normal, hzLightDir()) + wrap) / (1.0 + wrap), 0.0, 1.0);

	shadow = hzShadowAt(playerPos, normal);
	lighting += hzDirectLight() * (ndl * skyLight) * shadow;
#endif

	float hemisphere = dot(normal, hzUpDir()) * 0.5 + 0.5;
	lighting += mix(hzGroundColour(), hzAmbientColour(), hemisphere) * skyLight;

	lighting += vec3(hzAmbientFloor());
	lighting *= 1.0 + nightVision * 2.2;
	lighting *= mix(1.0, 0.02, blindness);

	shadowOut = shadow;

	return lighting;
}

// Specular highlight for smooth surfaces (water, slime, ...).
// viewDir and lightDir are in view space, both normalised.
float hzSpecular(vec3 normal, vec3 viewDir, vec3 lightDir, float shininess) {
	vec3 halfVector = normalize(lightDir + viewDir);
	float ndh = max(dot(normal, halfVector), 0.0);
	return pow(ndh, shininess);
}

//------------------------------------------------------------------------------
// Full shading of an opaque, non emissive surface. Returns linear HDR colour
// with atmospheric fog already applied, ready to be written to colortex0.
//   albedo       linear surface colour
//   viewNormal   view space normal
//   viewPos      view space position
//   playerPos    camera relative world position
//   lmCoord      lightmap coordinate
//   emissive     extra self illumination in [0, 1], added on top of albedo
//------------------------------------------------------------------------------
vec3 hzShadeSurface(vec3 albedo, vec3 viewNormal, vec3 viewPos, vec3 playerPos,
                    vec2 lmCoord, float emissive) {
	vec3 lighting = hzLighting(playerPos, viewNormal, lmCoord);
	vec3 colour = albedo * lighting;

	colour += albedo * (emissive * 2.6);

	return hzApplyFog(colour, viewPos, playerPos);
}

// Variant for fullbright things that ignore the lightmap (glint, spider eyes).
vec3 hzShadeFullbright(vec3 albedo, vec3 viewPos, vec3 playerPos, float strength) {
	vec3 colour = albedo * (hzFullbrightLighting() * strength);
	return hzApplyFog(colour, viewPos, playerPos);
}

#endif // HZ_LIGHTING_GLSL
