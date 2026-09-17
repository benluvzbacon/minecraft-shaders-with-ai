//==============================================================================
//
//   Horizon Shaders  -  procedural sky
//
//   Vanilla's sky, sun, moon and stars are disabled from shaders.properties and
//   are drawn here instead, in the deferred pass, for every pixel that did not
//   receive any geometry. The same functions are reused for water reflections.
//
//   Colours are linear HDR: the sun disc is far above 1.0 on purpose so that the
//   bloom pass has something to pick up.
//
//==============================================================================

#if !defined(HZ_SKY_GLSL)
#define HZ_SKY_GLSL

#include "/lib/dimension.glsl"

// Apparent radius of the sun and the moon, as a cosine of the view angle.
#define HZ_SUN_COS      0.99885
#define HZ_SUN_SOFTNESS 0.00045
#define HZ_MOON_COS     0.99935
#define HZ_MOON_SOFTNESS 0.00035

#define HZ_STAR_GRID    110.0
#define HZ_CLOUD_SCALE  0.00085
#define HZ_CLOUD_MAX_DIST 12000.0

// Direction in "celestial space": the world direction rotated about the world X
// axis so that the pattern follows the sun across the sky.
vec3 hzCelestialDir(vec3 worldDir) {
	vec3 sunWorld = normalize(hzWorldDirFromView(hzSunDir()));
	float theta = atan(sunWorld.z, sunWorld.y);
	return hzRotateX(-theta) * worldDir;
}

//---------------------------------- gradient ----------------------------------

vec3 hzSkyGradient(vec3 viewDir) {
	float up = dot(normalize(viewDir), hzUpDir());
	float horizonFade = pow(1.0 - hzClamp01(up), 3.4);

#if HZ_DIM_ID == 2
	// The End: a dark violet dome, no atmosphere to speak of.
	vec3 zenith = vec3(0.0035, 0.0030, 0.0110);
	vec3 horizon = vec3(0.0320, 0.0210, 0.0560);
	vec3 colour = mix(zenith, horizon, horizonFade);

	// Faint nebula band so the sky is not completely flat.
	vec3 worldDir = normalize(hzWorldDirFromView(normalize(viewDir)));
	float nebula = hzFbm2(vec2(atan(worldDir.z, worldDir.x) * 2.2, worldDir.y * 3.0), 3);
	colour += vec3(0.030, 0.018, 0.052) * pow(nebula, 2.2);

	return colour;
#elif HZ_DIM_ID == 1
	// The Nether has no sky at all, everything above the ceiling is the
	// dimension haze.
	return hzFogColour();
#else
	vec3 zenith = mix(vec3(0.0055, 0.0105, 0.0270), vec3(0.105, 0.275, 0.660), hzDayFactor());
	vec3 horizon = mix(vec3(0.0260, 0.0400, 0.0780), vec3(0.560, 0.710, 0.910), hzDayFactor());

	zenith = mix(zenith, vec3(0.140, 0.150, 0.390), hzTwilightFactor() * 0.80);
	horizon = mix(horizon, vec3(0.920, 0.430, 0.190), hzTwilightFactor() * 0.95);

	vec3 colour = mix(zenith, horizon, horizonFade);

	// Below the horizon, blend into the ground haze.
	colour = mix(colour, hzFogColour(), smoothstep(0.02, -0.20, up));

	// Storms turn the sky into a grey sheet.
	vec3 overcast = mix(vec3(0.200, 0.215, 0.250), vec3(0.050, 0.055, 0.070), hzNightFactor());
	colour = mix(colour, overcast, rainStrength * 0.92);

	return colour;
#endif
}

//------------------------------------ sun -------------------------------------

vec3 hzSunDisc(vec3 viewDir) {
#if !HZ_HAS_SUN
	return vec3(0.0);
#endif

	float sunDot = dot(normalize(viewDir), hzSunDir());
	float disc = smoothstep(HZ_SUN_COS - HZ_SUN_SOFTNESS, HZ_SUN_COS + HZ_SUN_SOFTNESS, sunDot);
	float innerGlow = pow(max(sunDot, 0.0), 420.0);
	float outerGlow = pow(max(sunDot, 0.0), 9.0);

	float visibility = 1.0 - rainStrength;
	vec3 colour = hzSunColour();

	vec3 result = colour * (disc * 17.0 + innerGlow * 0.85);
	result += colour * (outerGlow * 0.045 * hzDayFactor());

	return result * visibility;
}

//------------------------------------ moon ------------------------------------

vec3 hzMoonDisc(vec3 viewDir) {
#if !HZ_HAS_MOON
	return vec3(0.0);
#endif

	vec3 direction = normalize(viewDir);
	vec3 moonDir = hzMoonDir();
	float moonDot = dot(direction, moonDir);

	// Orthonormal basis on the moon disc. The up vector degenerates when the
	// moon sits exactly at the zenith or the nadir, so fall back to +X there.
	vec3 tangent = cross(hzUpDir(), moonDir);
	float tangentLength = length(tangent);

	if (tangentLength < 1e-4) {
		tangent = cross(vec3(1.0, 0.0, 0.0), moonDir);
		tangentLength = length(tangent);
	}

	tangent /= max(tangentLength, 1e-5);
	vec3 bitangent = cross(moonDir, tangent);

	float glow = pow(max(moonDot, 0.0), 900.0) * 0.10;
	vec3 glowColour = hzMoonColour() * glow * (1.0 - rainStrength);

	float disc = smoothstep(HZ_MOON_COS - HZ_MOON_SOFTNESS, HZ_MOON_COS + HZ_MOON_SOFTNESS, moonDot);

	if (disc <= 0.0) {
		return glowColour;
	}

	// Disc local coordinates, normalised so that the rim is at length 1.
	float sinRadius = sqrt(max(1.0 - HZ_MOON_COS * HZ_MOON_COS, 1e-6));
	vec2 discUv = vec2(dot(direction, tangent), dot(direction, bitangent)) / sinRadius;

	// Minecraft always places the moon exactly opposite the sun, so the real
	// geometry would always be a full moon. The phase is therefore driven by the
	// moonPhase uniform while the orientation of the lit limb still follows the
	// sun, which is what makes the crescent point the right way.
	float phaseAngle = float(moonPhase) * HZ_PI * 0.25;
	vec2 sunInPlane = vec2(dot(hzSunDir(), tangent), dot(hzSunDir(), bitangent));
	float sunInPlaneLength = length(sunInPlane);

	if (sunInPlaneLength < 1e-4) {
		sunInPlane = vec2(1.0, 0.0);
	} else {
		sunInPlane /= sunInPlaneLength;
	}

	vec3 lightDir = vec3(sunInPlane * sin(phaseAngle), cos(phaseAngle));
	float inside = max(1.0 - dot(discUv, discUv), 0.0);
	vec3 surfaceNormal = vec3(discUv, sqrt(inside));
	float lit = smoothstep(-0.03, 0.07, dot(surfaceNormal, lightDir));

	// A little mottling so the moon is not a flat disc.
	float craters = hzFbm2(discUv * 3.4 + 11.7, 3);
	vec3 surface = mix(vec3(0.42, 0.43, 0.47), vec3(0.72, 0.73, 0.76), craters);

	vec3 moonColour = surface * (2.6 * lit) * (0.45 + 0.55 * hzMoonIllumination());

	return glowColour + moonColour * disc * (1.0 - rainStrength * 0.85);
}

//------------------------------------ stars -----------------------------------

float hzStarField(vec3 worldDir) {
#if !HZ_HAS_STARS
	return 0.0;
#endif
#ifndef STARS
	return 0.0;
#endif

	vec3 celestial = hzCelestialDir(worldDir);
	vec3 scaled = celestial * HZ_STAR_GRID;
	vec3 cell = floor(scaled);
	vec3 local = scaled - cell - 0.5;
	vec3 random = hzHash33(cell);

	float presence = step(1.0 - 0.05 * STAR_DENSITY, random.x);
	vec3 offset = (random - 0.5) * 0.72;
	float distance = length(local - offset);

	float core = exp(-distance * distance * 46.0);
	float brightness = 0.30 + pow(random.y, 5.0) * 3.4;
	float twinkle = 0.70 + 0.30 * sin(frameTimeCounter * (1.4 + random.z * 5.0) + random.z * 62.8);

	return presence * core * brightness * twinkle;
}

vec3 hzStarColour(vec3 worldDir) {
	float stars = hzStarField(worldDir);

	if (stars <= 0.0) {
		return vec3(0.0);
	}

	// Slight per star colour temperature, from blue white to warm.
	vec3 random = hzHash33(floor(hzCelestialDir(worldDir) * HZ_STAR_GRID));
	vec3 tint = mix(vec3(0.72, 0.80, 1.00), vec3(1.00, 0.86, 0.68), random.z);

	// Milky way band across the sky.
	vec3 celestial = hzCelestialDir(worldDir);
	float band = exp(-pow(dot(celestial, normalize(vec3(0.42, 0.28, 0.86))) * 2.6, 2.0));
	float dust = hzFbm2(vec2(atan(celestial.z, celestial.x) * 1.8, celestial.y * 2.4) * 2.0, 4);
	float milkyWay = band * pow(dust, 1.6) * 0.055;

	return tint * stars + vec3(0.62, 0.68, 0.95) * milkyWay;
}

//------------------------------------ clouds ----------------------------------

vec2 hzCloudWind() {
	return vec2(frameTimeCounter * 0.42, frameTimeCounter * 0.07) * CLOUD_SPEED;
}

float hzCloudDensity(vec2 uv) {
	return hzFbm2(uv, CLOUD_OCTAVES);
}

// Returns vec4(colour, coverage). worldDir is a normalised world space
// direction, worldOrigin the absolute world position of the camera.
vec4 hzCloudLayer(vec3 worldDir, vec3 worldOrigin) {
#if !HZ_HAS_CLOUDS
	return vec4(0.0);
#endif
#ifndef CLOUDS
	return vec4(0.0);
#endif

	float altitude = CLOUD_ALTITUDE;
	float cameraY = worldOrigin.y;

	// Only rays that actually reach the cloud plane from below.
	if (worldDir.y < 0.008) {
		return vec4(0.0);
	}

	float rayDistance = (altitude - cameraY) / worldDir.y;

	if (rayDistance < 0.0 || rayDistance > HZ_CLOUD_MAX_DIST) {
		return vec4(0.0);
	}

	vec2 position = worldOrigin.xz + worldDir.xz * rayDistance;
	vec2 uv = position * HZ_CLOUD_SCALE + hzCloudWind();

	float density = hzCloudDensity(uv);
	float threshold = 1.0 - CLOUD_DENSITY;
	float coverage = smoothstep(threshold, threshold + 0.22, density);

	if (coverage <= 0.0) {
		return vec4(0.0);
	}

	// Fake self shadowing by comparing the density with a sample pushed towards
	// the sun. This is the classic two sample 2D cloud lighting trick.
	vec3 sunWorld = normalize(hzWorldDirFromView(hzSunDir()));
	vec2 sunOffset = sunWorld.xz * max(sunWorld.y, 0.0) * 0.055;
	float sunSample = hzCloudDensity(uv + sunOffset);
	float thickness = hzClamp01((density - sunSample) * 3.2);
	float lighting = mix(0.34, 1.0, thickness);

	// Clouds far away melt into the haze.
	float distanceFade = 1.0 - smoothstep(HZ_CLOUD_MAX_DIST * 0.35, HZ_CLOUD_MAX_DIST * 0.95, rayDistance);
	float horizonFade = smoothstep(0.008, 0.075, worldDir.y);

	vec3 dayColour = mix(vec3(1.05, 1.06, 1.10), hzSunColour() * 1.35, hzTwilightFactor() * 0.75);
	vec3 nightColour = vec3(0.11, 0.13, 0.19);
	vec3 cloudColour = mix(nightColour, dayColour, hzDayFactor()) * lighting;

	// Storm clouds are dark and heavy.
	cloudColour = mix(cloudColour, vec3(0.13, 0.14, 0.16) * lighting, rainStrength * 0.88);
	coverage = mix(coverage, min(1.0, coverage + rainStrength * 0.55), rainStrength);

	return vec4(cloudColour, coverage * distanceFade * horizonFade);
}

//--------------------------------- composition --------------------------------

// Full sky for a view space direction.
vec3 hzSky(vec3 viewDir) {
	vec3 direction = normalize(viewDir);

	vec3 colour = hzSkyGradient(direction);

#if HZ_HAS_STARS
	vec3 worldDir = normalize(hzWorldDirFromView(direction));

	float up = dot(direction, hzUpDir());
	float starVisibility = hzNightFactor() * (1.0 - rainStrength) * smoothstep(-0.02, 0.16, up);

#if HZ_DIM_ID == 2
	starVisibility = (1.0 - rainStrength) * smoothstep(-0.02, 0.10, up);
#endif

	colour += hzStarColour(worldDir) * starVisibility;
#endif

	colour += hzSunDisc(direction);
	colour += hzMoonDisc(direction);

#if HZ_HAS_CLOUDS
	{
		vec3 worldDir = normalize(hzWorldDirFromView(direction));
		vec4 clouds = hzCloudLayer(worldDir, hzWorldPos(vec3(0.0)));
		colour = mix(colour, clouds.rgb, clouds.a);
	}
#endif

#if HZ_HAS_SKY
	// Vanilla draws a black "dark sky" plane under the world so that falling out of
	// it does not show the sky. That plane is a coloured sky quad, which
	// gbuffers_skybasic discards (see the comment in that program), so the same
	// effect is reproduced here: once the camera drops under the world floor the
	// downward half of the sky darkens to almost nothing.
	{
		float cameraY = hzWorldPos(vec3(0.0)).y;
		float below = smoothstep(float(bedrockLevel) + 4.0, float(bedrockLevel) - 8.0, cameraY);
		float downward = smoothstep(0.02, -0.25, dot(direction, hzUpDir()));
		colour *= mix(1.0, 0.015, below * downward);
	}
#endif

	return colour;
}

// Cheaper variant used for reflections on water and other smooth surfaces: the
// cloud layer is the expensive part, so it is skipped on the lowest setting.
vec3 hzSkyReflection(vec3 viewDir) {
	vec3 direction = normalize(viewDir);
	vec3 colour = hzSkyGradient(direction);

	colour += hzSunDisc(direction);
	colour += hzMoonDisc(direction);

#if HZ_HAS_CLOUDS && WATER_QUALITY > 0
	{
		vec3 worldDir = normalize(hzWorldDirFromView(direction));
		vec4 clouds = hzCloudLayer(worldDir, hzWorldPos(vec3(0.0)));
		colour = mix(colour, clouds.rgb, clouds.a);
	}
#endif

	return colour;
}

#endif // HZ_SKY_GLSL
