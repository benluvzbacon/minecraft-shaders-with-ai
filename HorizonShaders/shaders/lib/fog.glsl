//==============================================================================
//
//   Horizon Shaders  -  fog (fragment stages only)
//
//   Vanilla fog is not applied by Iris when a shader pack is loaded, the pack
//   has to do it. The uniforms below are the ones Iris fills in for every world
//   program, and hzVanillaFogFactor() reproduces exactly what Iris' own
//   fallback shader does (see net.irisshaders.iris.pipeline.fallback
//   .ShaderSynthesizer), so distance fog matches vanilla per dimension:
//     fogMode 0 = disabled (composite stages), 2049 = GL_EXP2, 9729 = GL_LINEAR
//     fogShape 0 = spherical, 1 = cylindrical
//
//==============================================================================

#if !defined(HZ_FOG_GLSL)
#define HZ_FOG_GLSL

#include "/lib/dimension.glsl"

#define HZ_FOG_MODE_LINEAR 9729
#define HZ_FOG_MODE_EXP2   2049

float hzFogDistance(vec3 viewPos) {
	if (fogShape == 1) {
		return length(vec3(viewPos.x, 0.0, viewPos.z));
	}
	return length(viewPos);
}

// 1.0 = no fog, 0.0 = fully fogged. Same formula as vanilla/Iris.
float hzVanillaFogFactor(float distance) {
	float factor;

	if (fogMode == HZ_FOG_MODE_EXP2) {
		float scaled = distance * fogDensity;
		factor = exp(-scaled * scaled);
	} else if (fogMode == HZ_FOG_MODE_LINEAR) {
		factor = (fogEnd - distance) / max(fogEnd - fogStart, HZ_EPS);
	} else {
		factor = 1.0;
	}

	return clamp(factor, 0.0, 1.0);
}

// Fog colour in linear light, with a bit of forward scattering towards the sun
// so that sunrise and sunset actually tint the haze.
vec3 hzAtmosphericFogColour(vec3 viewDir, vec3 playerPos) {
	vec3 colour = hzFogColour();

#if HZ_HAS_SUN
	float sunAlignment = max(dot(normalize(viewDir), hzSunDir()), 0.0);
	float glow = pow(sunAlignment, 7.0) * (0.20 * hzDayFactor() + 0.55 * hzTwilightFactor());
	colour += hzSunColour() * glow * (1.0 - rainStrength * 0.9) * ATMOSPHERE_STRENGTH;

	float moonAlignment = max(dot(normalize(viewDir), hzMoonDir()), 0.0);
	colour += hzMoonColour() * pow(moonAlignment, 12.0) * (0.10 * hzNightFactor()) * ATMOSPHERE_STRENGTH;
#endif

#if HZ_DIM_ID == 1
	// Nether: warm glow rising from the lava sea below.
	float worldY = hzWorldPos(playerPos).y;
	colour += vec3(0.42, 0.09, 0.02) * exp(-max(worldY - 31.0, 0.0) / 16.0) * 0.55;
#elif HZ_DIM_ID == 2
	// End: the void below the islands swallows light.
	float worldY = hzWorldPos(playerPos).y;
	colour *= 1.0 - 0.55 * exp(-max(worldY - 8.0, 0.0) / 26.0);
#endif

	return colour;
}

// Shared fog factor: the vanilla curve, unmodified, plus blindness.
// 1.0 = no fog, 0.0 = fully fogged. There is deliberately no density
// multiplier and no border fog here: distance fog has to stay exactly what
// Minecraft and the render distance setting make it, and the atmospheric
// work lives in the fog *colour*, scaled by ATMOSPHERE_STRENGTH.
float hzFogFactorFor(vec3 viewPos) {
	float distance = hzFogDistance(viewPos);
	float factor = hzVanillaFogFactor(distance);

	// Blindness / darkness effect pulls everything towards black fog.
	return factor * mix(1.0, 0.06, blindness);
}

// Applies atmospheric fog to an already lit, linear HDR colour.
vec3 hzApplyFog(vec3 colour, vec3 viewPos, vec3 playerPos) {
	float factor = hzFogFactorFor(viewPos);

	vec3 fogColour = hzAtmosphericFogColour(normalize(viewPos), playerPos);
	fogColour *= mix(1.0, 0.02, blindness);

	return mix(fogColour, colour, factor);
}

// Fog for additively blended geometry (spider eyes, armor glint, lightning).
// An additive pass has no destination colour to mix towards, so blending in the
// fog colour would make the geometry glow like a light source; scaling it down
// by the fog factor is the correct thing to do there.
vec3 hzApplyFogAdditive(vec3 colour, vec3 viewPos) {
	return colour * hzFogFactorFor(viewPos);
}

//-------------------------------- water fog -----------------------------------

vec3 hzWaterFogColour() {
	// The water tint depends on the biome a little; temperature and rainfall are
	// the only per pixel information available, which is enough to make swamps
	// and cold oceans read differently.
	vec3 base = vec3(0.030, 0.130, 0.190);
	vec3 cold = vec3(0.045, 0.115, 0.215);
	vec3 warm = vec3(0.055, 0.155, 0.140);

	vec3 colour = mix(base, cold, hzClamp01(1.0 - temperature));
	colour = mix(colour, warm, hzClamp01(temperature - 0.6) * hzClamp01(rainfall + 0.4));

	// Light coming down from above the surface.
	float eyeSky = float(eyeBrightnessSmooth.y) / 240.0;
	colour *= 0.18 + eyeSky * 1.15;

	return colour * (0.35 + 0.9 * hzDayFactor());
}

// Underwater / lava / powder snow fog, applied on top of the regular fog when
// the camera itself is inside a fluid.
vec3 hzApplyMediaFog(vec3 colour, vec3 viewPos) {
	if (isEyeInWater == 0) {
		return colour;
	}

	float distance = hzFogDistance(viewPos);

	if (isEyeInWater == 2) {
		// Lava: bright, dense, orange.
		float factor = exp(-distance * 2.4);
		return mix(vec3(0.85, 0.28, 0.045) * 1.25, colour, factor);
	}

	if (isEyeInWater == 3) {
		// Powder snow: whiteout.
		float factor = exp(-distance * 1.6);
		return mix(vec3(0.72, 0.76, 0.80), colour, factor);
	}

	// Water.
	float density = 0.085 * UNDERWATER_DENSITY;
	float factor = exp(-distance * density);

	// Looking up towards the surface lets more light through.
	float upAlignment = max(dot(normalize(viewPos), hzUpDir()), 0.0);
	vec3 waterColour = hzWaterFogColour() * (1.0 + upAlignment * 0.55);

	return mix(waterColour, colour, hzClamp01(factor));
}

#endif // HZ_FOG_GLSL
