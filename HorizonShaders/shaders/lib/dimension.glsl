//==============================================================================
//
//   Horizon Shaders  -  dimension handling
//
//   Iris loads shaders/world-1/*.glsl for the Nether and shaders/world1/*.glsl
//   for the End. Those directories are complete program sets whose sources only
//   add `#define DIM_NETHER` / `#define DIM_END` before including the Overworld
//   program, so every dimension difference is handled from here.
//
//   NOTE: the checks below deliberately use `#if defined(...)` instead of
//   `#ifdef`, otherwise Iris would register DIM_NETHER / DIM_END as boolean
//   shader options and show them in the settings menu.
//
//==============================================================================

#if !defined(HZ_DIMENSION_GLSL)
#define HZ_DIMENSION_GLSL

#include "/lib/common.glsl"
#include "/lib/color.glsl"

#if defined(DIM_NETHER)
	#define HZ_DIM_ID 1
#elif defined(DIM_END)
	#define HZ_DIM_ID 2
#else
	#define HZ_DIM_ID 0
#endif

// Capability switches --------------------------------------------------------
#define HZ_HAS_SKY     (HZ_DIM_ID != 1)
#define HZ_HAS_SUN     (HZ_DIM_ID == 0)
#define HZ_HAS_MOON    (HZ_DIM_ID == 0)
#define HZ_HAS_STARS   (HZ_DIM_ID != 1)
#define HZ_HAS_CLOUDS  (HZ_DIM_ID == 0)
#define HZ_HAS_WEATHER (HZ_DIM_ID == 0)
#define HZ_HAS_SHADOWS (HZ_DIM_ID != 1)

//--------------------------------- celestial ----------------------------------

vec3 hzUpDir() {
	return normalize(upPosition);
}

// Sun and moon directions in view space (Iris gives them in view space).
vec3 hzSunDir() {
	return normalize(sunPosition);
}

vec3 hzMoonDir() {
	return normalize(moonPosition);
}

// Direction the shadow map was rendered from: the sun by day, the moon by night.
vec3 hzLightDir() {
	return normalize(shadowLightPosition);
}

float hzSunHeight() {
	return dot(hzSunDir(), hzUpDir());
}

float hzMoonHeight() {
	return dot(hzMoonDir(), hzUpDir());
}

// 0.0 at night, 1.0 at day, smooth through sunrise and sunset.
float hzDayFactor() {
#if HZ_HAS_SUN
	return smoothstep(-0.10, 0.14, hzSunHeight());
#else
	return 0.0;
#endif
}

float hzNightFactor() {
	return 1.0 - hzDayFactor();
}

// Peaks while the sun sits on the horizon.
float hzTwilightFactor() {
#if HZ_HAS_SUN
	return 1.0 - smoothstep(0.0, 0.42, abs(hzSunHeight()));
#else
	return 0.0;
#endif
}

float hzMoonIllumination() {
#if HZ_HAS_MOON
	return 0.5 + 0.5 * cos(float(moonPhase) * HZ_PI * 0.25);
#else
	return 0.0;
#endif
}

//--------------------------------- light colour -------------------------------

vec3 hzSunColour() {
	vec3 noon = vec3(1.00, 0.94, 0.84);
	vec3 horizon = vec3(1.00, 0.52, 0.26);
	vec3 colour = mix(noon, horizon, hzTwilightFactor());

	// Storms desaturate and dim the sun. rainStrength is always 0 in
	// dimensions without weather, so no extra guard is needed here.
	colour = mix(colour, vec3(0.62, 0.64, 0.68), rainStrength * 0.85);

	return colour;
}

vec3 hzMoonColour() {
	return vec3(0.42, 0.56, 0.86);
}

// Directional light colour * intensity for the main shadow casting light.
vec3 hzDirectLight() {
#if HZ_HAS_SUN
	float storm = rainStrength;
	// Noon direct light lands a lit white block just above 1.0 in HDR, so the
	// tonemap shoulder - not the clamp - is what handles bright surfaces.
	float sunStrength = mix(1.00, 0.28, storm);
	float moonStrength = 0.18 * (0.35 + 0.65 * hzMoonIllumination());

	vec3 sun = hzSunColour() * (sunStrength * SUNLIGHT_STRENGTH);
	vec3 moon = hzMoonColour() * (moonStrength * MOONLIGHT_STRENGTH);

	return mix(moon, sun, hzDayFactor());
#elif HZ_DIM_ID == 2
	// The End has no sun, but a cold directional "void light" keeps the
	// geometry readable and gives the shadow map something to do.
	return vec3(0.62, 0.60, 0.86) * (0.55 * SUNLIGHT_STRENGTH);
#else
	return vec3(0.0);
#endif
}

// Sky / ambient colour used for the hemisphere ambient term.
vec3 hzAmbientColour() {
#if HZ_DIM_ID == 0
	vec3 day = vec3(0.42, 0.58, 0.86);
	vec3 twilight = vec3(0.46, 0.36, 0.42);
	vec3 night = vec3(0.075, 0.10, 0.17);

	vec3 colour = mix(night, day, hzDayFactor());
	colour = mix(colour, twilight, hzTwilightFactor() * 0.65);
	colour = mix(colour, vec3(0.28, 0.30, 0.34), rainStrength * 0.8);

	return colour * (0.90 * AMBIENT_STRENGTH);
#elif HZ_DIM_ID == 1
	// Nether: no sky at all, just the glow of the dimension itself. Iris
	// reports a non zero ambientLight there.
	return vec3(0.62, 0.20, 0.10) * ((0.55 + ambientLight * 3.0) * AMBIENT_STRENGTH);
#else
	return vec3(0.24, 0.20, 0.42) * ((0.55 + ambientLight * 3.0) * AMBIENT_STRENGTH);
#endif
}

// Ground bounce light (the lower hemisphere of the ambient term).
vec3 hzGroundColour() {
#if HZ_DIM_ID == 0
	return vec3(0.20, 0.17, 0.13) * (0.45 * AMBIENT_STRENGTH);
#elif HZ_DIM_ID == 1
	return vec3(0.30, 0.10, 0.05) * (0.55 * AMBIENT_STRENGTH);
#else
	return vec3(0.13, 0.10, 0.20) * (0.45 * AMBIENT_STRENGTH);
#endif
}

// Vanilla already hands us a per dimension fog colour, the End and the Nether
// just need a small correction to keep them from looking washed out.
vec3 hzFogColour() {
	vec3 colour = hzSrgbToLinear(fogColor);

#if HZ_DIM_ID == 2
	colour = mix(colour, vec3(0.030, 0.020, 0.055), 0.55);
#elif HZ_DIM_ID == 1
	colour *= 0.85;
#endif

	return colour;
}

// Sky colour at the horizon, used to blend terrain into the sky.
vec3 hzHorizonColour() {
	return hzFogColour();
}

#endif // HZ_DIMENSION_GLSL
