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
#define HZ_CLOUD_SCALE  0.0045
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
//
//   The deck is a slab between CLOUD_ALTITUDE and CLOUD_ALTITUDE + thickness.
//   A view ray is intersected with that slab and integrated in a few layers,
//   each layer sampling the same warped fBm coverage field at its own point on
//   the ground plane. Integrating along the ray - instead of sampling the plane
//   once, like the first version of this pack did - is what puts clouds
//   overhead: a single plane sample only ever shows whatever one point of the
//   noise field happens to be, and everything else collapses into a thin band
//   at the horizon.
//
//   The result is returned as (in-scattered light, transmittance) so the caller
//   can composite it exactly: colour = colour * transmittance + scatter.
//
//------------------------------------------------------------------------------

// Thickness of the cumulus deck in blocks.
#define HZ_CLOUD_THICKNESS  46.0
// How quickly light dies inside the deck, per unit density per metre.
#define HZ_CLOUD_EXTINCTION 0.16
// Altitude of the thin cirrus layer, as a multiple of the deck altitude.
#define HZ_CIRRUS_ALTITUDE  2.7

// Drift of the deck in blocks per second, converted into field space here so
// the speed stays the same no matter what HZ_CLOUD_SCALE is.
vec2 hzCloudWind() {
	return vec2(frameTimeCounter * 4.0, frameTimeCounter * 0.7) * CLOUD_SPEED * HZ_CLOUD_SCALE;
}

// Warped fBm coverage field, shared by the sky, the water reflection and the
// shadows the deck throws on the ground, so that all three always agree.
float hzCloudField(vec2 worldXZ) {
	vec2 uv = worldXZ * HZ_CLOUD_SCALE + hzCloudWind();

	// Domain warp: two cheap noise samples push the lookup around, which is what
	// turns axis aligned blobs into weather.
	vec2 warp = vec2(hzNoise2(uv * 0.31 + 7.31), hzNoise2(uv * 0.31 - 4.17)) - 0.5;

	return hzFbm2(uv + warp * 0.80, CLOUD_OCTAVES);
}

// Coverage 0..1 for a field value. CLOUD_DENSITY moves the threshold through
// the upper half of the field's range - the field is a normalised fBm centred
// on 0.5, so a threshold near 1 - density would leave almost everything above
// it and paint a milky overcast sheet instead of broken clouds.
float hzCloudCoverage(float field) {
	float threshold = mix(0.68, 0.42, CLOUD_DENSITY);

	return smoothstep(threshold, threshold + 0.15, field);
}

// Colour of the light that illuminates the deck: the sun by day, the moon and
// the night sky after dusk, a grey sheet in a storm.
vec3 hzCloudLightColour() {
	vec3 day = hzSunColour() * 1.30;
	vec3 night = vec3(0.135, 0.165, 0.260) * (0.35 + 0.65 * hzMoonIllumination());
	vec3 colour = mix(night, day, hzDayFactor());

	return mix(colour, vec3(0.30, 0.315, 0.345), rainStrength * 0.85);
}

// Ambient the deck is bathed in, brighter towards the top of the slab.
vec3 hzCloudAmbient(float height) {
	vec3 day = mix(vec3(0.22, 0.26, 0.34), vec3(0.50, 0.60, 0.78), height);
	vec3 night = mix(vec3(0.020, 0.024, 0.038), vec3(0.055, 0.065, 0.100), height);

	return mix(night, day, hzDayFactor());
}

vec4 hzCloudLayer(vec3 worldDir, vec3 worldOrigin) {
#if !HZ_HAS_CLOUDS
	return vec4(0.0);
#endif
#ifndef CLOUDS
	return vec4(0.0);
#endif

	vec3 direction = normalize(worldDir);

	// Rays that travel along the deck never leave it; there is nothing sane to
	// integrate there, and the fog owns the horizon anyway.
	if (abs(direction.y) < 0.004) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}

	float baseAltitude = CLOUD_ALTITUDE;
	float topAltitude = CLOUD_ALTITUDE + HZ_CLOUD_THICKNESS;

	// Slab intersection. Works from below and from above, so flying over the
	// deck shows its top side instead of nothing.
	float tBase = (baseAltitude - worldOrigin.y) / direction.y;
	float tTop = (topAltitude - worldOrigin.y) / direction.y;
	float enter = max(min(tBase, tTop), 0.0);
	float exit = min(max(tBase, tTop), HZ_CLOUD_MAX_DIST);

	if (exit <= enter) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}

	vec3 sunWorld = normalize(hzWorldDirFromView(hzSunDir()));
	float sunUp = max(sunWorld.y, 0.16);
	vec3 lightColour = hzCloudLightColour();
	// Metres of deck one layer sample stands for; extinction is per metre so
	// grazing rays correctly thicken instead of every angle looking the same.
	float stepLength = (exit - enter) / float(CLOUD_LAYERS);

	float transmittance = 1.0;
	vec3 scatter = vec3(0.0);

	for (int i = 0; i < CLOUD_LAYERS; i++) {
		if (transmittance < 0.03) {
			break;
		}

		// Height of this layer inside the slab, 0 at the base, 1 at the top.
		float height = (float(i) + 0.5) / float(CLOUD_LAYERS);
		float layerT = mix(enter, exit, height);
		vec3 point = worldOrigin + direction * layerT;

		// Flat base, eroded top: the vertical profile is what reads as a cloud
		// instead of a fog sheet.
		float profile = smoothstep(0.0, 0.18, height) * (1.0 - smoothstep(0.55, 1.0, height));

		float field = hzCloudField(point.xz);

		// Detail erosion, stronger near the top so the crowns stay wispy.
		float detail = hzFbm2(point.xz * (HZ_CLOUD_SCALE * 5.0) + hzCloudWind() * 1.6, 3);
		// The erosion frequencies alias far away, so let the detail melt back
		// into the base shape before the distance fade takes over.
		float detailWeight = (0.10 + 0.55 * height * height) * (1.0 - smoothstep(2500.0, 7000.0, layerT));
		float coverage = hzCloudCoverage(field - (1.0 - detail) * detailWeight);

		// Storms close the sky in.
		coverage = mix(coverage, min(1.0, coverage + 0.55), rainStrength);

		float density = coverage * profile;

		if (density <= 0.002) {
			continue;
		}

		//----------------------------- lighting -----------------------------
		// One sample towards the sun gives beer-lambert self shadowing; the
		// powder term puts a silver lining on the sun side of the cloud.
		vec2 sunPoint = point.xz + sunWorld.xz * (HZ_CLOUD_THICKNESS * (1.0 - height) / sunUp);
		float optical = hzCloudCoverage(hzCloudField(sunPoint)) * (1.0 - height * 0.35);
		float beer = exp(-optical * 3.0);
		float powder = 1.0 - exp(-density * 2.4);
		float forward = pow(clamp(dot(direction, sunWorld) * 0.5 + 0.5, 0.0, 1.0), 6.0);

		vec3 luminance = lightColour * (beer * (0.50 + 0.90 * powder) + forward * beer * 1.10)
			+ hzCloudAmbient(height);

		float extinction = density * HZ_CLOUD_EXTINCTION * stepLength;
		float absorbed = 1.0 - exp(-extinction);

		scatter += transmittance * absorbed * luminance;
		transmittance *= exp(-extinction);
	}

	//---------------------------------- cirrus --------------------------------
	// A thin stretched layer far above the deck. One extra sample, and the sky
	// stops looking like it has a single flat ceiling.
	if (direction.y > 0.02 && transmittance > 0.05) {
		float t = (CLOUD_ALTITUDE * HZ_CIRRUS_ALTITUDE - worldOrigin.y) / direction.y;

		if (t > 0.0 && t < HZ_CLOUD_MAX_DIST) {
			vec2 point = worldOrigin.xz + direction.xz * t;
			vec2 uv = point * (HZ_CLOUD_SCALE * 2.1) + hzCloudWind() * 0.30;
			float wisps = hzFbm2(uv * vec2(1.0, 2.7), 3);
			float cirrus = smoothstep(0.60, 0.86, wisps) * 0.40;

			cirrus = mix(cirrus, cirrus * 1.6, rainStrength);

			if (cirrus > 0.002) {
				vec3 luminance = lightColour * 0.85 + hzCloudAmbient(1.0);
				float absorbed = cirrus * 0.55;

				scatter += transmittance * absorbed * luminance;
				transmittance *= 1.0 - absorbed;
			}
		}
	}

	//--------------------------- distance and horizon -------------------------
	// The deck has to dissolve into the atmosphere before its edge can show, and
	// stay out of the fog band right at the horizon.
	float distanceFade = 1.0 - smoothstep(HZ_CLOUD_MAX_DIST * 0.30, HZ_CLOUD_MAX_DIST * 0.92, exit);
	float horizonFade = smoothstep(0.004, 0.030, abs(direction.y));
	float fade = distanceFade * horizonFade;

	return vec4(scatter * fade, mix(1.0, transmittance, fade));
}

// Fraction of the direct light that survives the deck, for the ground below:
// the coverage field sampled where the light ray from the shaded point enters
// the cloud base. lib/lighting.glsl multiplies this into the sun term, which is
// what makes clouds cast shadows without a single extra shadow map.
float hzCloudShadow(vec3 worldPos) {
#ifdef CLOUD_SHADOWS
#if HZ_HAS_CLOUDS
	vec3 lightWorld = normalize(hzWorldDirFromView(hzLightDir()));

	if (lightWorld.y < 0.08) {
		return 1.0;
	}

	float t = (CLOUD_ALTITUDE - worldPos.y) / lightWorld.y;

	if (t < 0.0 || t > HZ_CLOUD_MAX_DIST * 0.5) {
		return 1.0;
	}

	vec2 point = worldPos.xz + lightWorld.xz * t;
	float coverage = hzCloudCoverage(hzCloudField(point));

	coverage = mix(coverage, 1.0, rainStrength * 0.75);

	return 1.0 - coverage * 0.60;
#endif
#endif

	return 1.0;
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

		// in-scatter plus what the deck lets through
		colour = colour * clouds.w + clouds.rgb;
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

		colour = colour * clouds.w + clouds.rgb;
	}
#endif

	return colour;
}

#endif // HZ_SKY_GLSL
