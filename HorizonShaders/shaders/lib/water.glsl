//==============================================================================
//
//   Horizon Shaders  -  water surface helpers (fragment stages only)
//
//   The wave field is evaluated in absolute world space so that the surface
//   does not swim when the camera moves, and high frequency waves are faded out
//   with distance so that they cannot alias into sparkly noise.
//
//==============================================================================

#if !defined(HZ_WATER_GLSL)
#define HZ_WATER_GLSL

#include "/lib/sky.glsl"

// direction.x, direction.z, angular frequency (radians per block), amplitude
const vec4 HZ_WAVES[8] = vec4[8](
	vec4( 1.00,  0.20, 0.35, 0.220),
	vec4(-0.70,  0.75, 0.60, 0.140),
	vec4( 0.30, -1.00, 1.10, 0.075),
	vec4(-0.95, -0.35, 1.80, 0.045),
	vec4( 0.60,  0.85, 2.60, 0.026),
	vec4(-0.20,  0.50, 3.60, 0.015),
	vec4( 0.90, -0.65, 4.80, 0.009),
	vec4(-0.55, -0.90, 6.00, 0.005)
);

// Height field gradient of the wave sum, d(height)/d(x) and d(height)/d(z).
vec2 hzWaterGradient(vec2 worldXZ, float viewDistance) {
	vec2 gradient = vec2(0.0);

#ifdef WATER_WAVES
	// Storms make the surface choppy.
	float chop = 1.0 + rainStrength * 1.35;

	for (int i = 0; i < WATER_WAVE_COUNT; i++) {
		vec4 wave = HZ_WAVES[i];
		vec2 direction = normalize(wave.xy);

		// Fade the shorter waves out with distance, they are the ones that
		// would otherwise turn into shimmering noise on the horizon.
		float fade = exp(-wave.z * viewDistance * 0.020);

		float phase = dot(direction, worldXZ) * wave.z + frameTimeCounter * (0.55 + wave.z * 0.22);
		gradient += direction * (cos(phase) * wave.w * wave.z * chop * fade);
	}

	// Fine ripples on top, only close up.
	float rippleFade = exp(-viewDistance * 0.09);
	vec2 rippleUv = worldXZ * 2.6 + vec2(frameTimeCounter * 0.31, -frameTimeCounter * 0.19);
	gradient.x += (hzNoise2(rippleUv) - 0.5) * 0.16 * rippleFade;
	gradient.y += (hzNoise2(rippleUv + 37.4) - 0.5) * 0.16 * rippleFade;
#endif

	return gradient;
}

// Tangent space -> world space normal of the surface (Y is up in world space).
vec3 hzWaterWorldNormal(vec2 gradient, float strength) {
	return normalize(vec3(-gradient.x * strength, 1.0, -gradient.y * strength));
}

// Rough height of the wave field, used to fake crests and foam.
float hzWaterHeight(vec2 worldXZ) {
	float height = 0.0;

#ifdef WATER_WAVES
	for (int i = 0; i < WATER_WAVE_COUNT; i++) {
		vec4 wave = HZ_WAVES[i];
		vec2 direction = normalize(wave.xy);
		float phase = dot(direction, worldXZ) * wave.z + frameTimeCounter * (0.55 + wave.z * 0.22);
		height += sin(phase) * wave.w;
	}
#endif

	return height;
}

// Schlick approximation of the Fresnel term. f0 for water is about 0.02.
float hzFresnel(float cosTheta, float f0) {
	float x = hzClamp01(1.0 - cosTheta);
	float x2 = x * x;
	float x5 = x2 * x2 * x;
	return f0 + (1.0 - f0) * x5;
}

// Beer-Lambert absorption of the light travelling through the water body.
vec3 hzWaterTransmittance(float depth) {
	vec3 absorption = vec3(0.46, 0.105, 0.075);
	return exp(-absorption * max(depth, 0.0) * WATER_ABSORPTION);
}

// Colour of the water itself, the more of it there is the more it dominates.
vec3 hzWaterBody(float depth) {
	vec3 tint = vec3(0.020, 0.145, 0.185);
	float density = 1.0 - exp(-max(depth, 0.0) * WATER_TURBIDITY * 1.4);
	return tint * density * (0.35 + 0.9 * hzDayFactor() + ambientLight);
}

// Foam at the shoreline and on wave crests.
float hzFoam(float depth, float height) {
#ifndef WATER_FOAM
	return 0.0;
#else
	float shore = 1.0 - smoothstep(0.05, 0.42, depth);
	float crest = smoothstep(0.10, 0.30, height + rainStrength * 0.12);
	return hzClamp01(shore * 0.55 + crest * shore * 1.4 + crest * 0.10);
#endif
}

#endif // HZ_WATER_GLSL
