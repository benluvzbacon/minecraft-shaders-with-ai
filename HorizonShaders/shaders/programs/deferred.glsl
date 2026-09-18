//==============================================================================
//
//   Horizon Shaders  -  deferred
//
//   First fullscreen pass. Two jobs:
//
//   1. Resolve the water surface that gbuffers_water left in the material
//      buffer. This is the only place where the untouched background colour is
//      available, which is what makes screen space refraction possible at all.
//   2. Apply the media fog (underwater, lava, powder snow) to the whole frame,
//      sky included, so that it also covers the geometry that was drawn after
//      the water pass.
//
//   The result stays in linear HDR in colortex0; tone mapping happens later,
//   after bloom and the temporal filter.
//
//==============================================================================

#include "/lib/composite_common.glsl"
#include "/lib/lighting.glsl"
#include "/lib/water.glsl"
#include "/lib/material.glsl"

uniform sampler2D colortex3;
uniform sampler2D colortex5;

#if defined(HZ_STAGE_VERTEX)

void main() {
	hzCompositeVertex();
}

#endif // HZ_STAGE_VERTEX

#if defined(HZ_STAGE_FRAGMENT)

/* RENDERTARGETS:0 */

//------------------------------------------------------------------------------
// Composites the water surface over the background that is already in the scene
// buffer.
//   background    colortex0 as gbuffers_water left it (untouched by the water)
//   waterData     colortex3: normal.xy, surface depth / far, sky light level
//   tintData      colortex5: biome tint, foam
//------------------------------------------------------------------------------
vec3 hzResolveWater(vec2 uv, vec3 background, vec3 viewPos, vec3 playerPos,
                    vec4 waterData, vec4 tintData, float surfaceDepth) {
	vec3 viewDir = normalize(viewPos);
	vec3 normal = hzDecodeWaterNormal(waterData.xy, viewDir);

	float skyLightLevel = waterData.w;
	float backgroundDepth = texture2D(depthtex1, uv).r;
	float waterDepth = max(hzLinearDepth(backgroundDepth) - hzLinearDepth(surfaceDepth), 0.0);

	//------------------------------------------------------------- refraction --
	vec3 refracted = background;

#ifdef WATER_REFRACTION
	{
		// Displace the background sample along the surface normal. The offset
		// shrinks with depth so that a far shore does not smear into a swirl.
		float strength = 0.085 / (1.0 + waterDepth * 0.25);
		vec2 refractUv = hzClamp01(uv + normal.xy * strength);

		// Never pull geometry that sits in front of the water into the refracted
		// image; that would make a near shore appear on top of the deep water.
		float sampleDepth = texture2D(depthtex1, refractUv).r;

		if (hzIsSky(sampleDepth) || sampleDepth >= surfaceDepth) {
			refracted = texture2D(colortex0, refractUv).rgb;
		}
	}
#endif

	//------------------------------------------------------------------ colour --
	// The biome tint is normalised to a hue plus a strength, so that a dark swamp
	// tint colours the water without also crushing it.
	vec3 tint = tintData.rgb;
	float tintMax = max(max(tint.r, tint.g), max(tint.b, HZ_EPS));
	vec3 tintHue = tint / tintMax;
	float tintStrength = hzClamp01(tintMax * 3.0);
	vec3 absorptionTint = mix(vec3(1.0), tintHue, tintStrength);

	vec3 transmittance = hzWaterTransmittance(waterDepth);
	transmittance *= mix(vec3(1.0), absorptionTint, hzClamp01(waterDepth * 0.25));

	vec3 body = hzWaterBody(waterDepth) * mix(vec3(1.0), absorptionTint, 0.75);

	vec3 shadow = vec3(1.0);
	vec3 surfaceLight = hzLightingSkyOnly(playerPos, normal, skyLightLevel, shadow);

	// The body swallows the background progressively with depth, so a pond
	// reads as water instead of as a window into its bed.
	float opacity = hzWaterOpacity(waterDepth);
	vec3 colour = refracted * transmittance * (1.0 - opacity * 0.85)
		+ body * surfaceLight * (0.45 + 0.55 * opacity);

	//--------------------------------------------------------------- reflection --
	float cosTheta = max(dot(-viewDir, normal), 0.0);
	float fresnel = hzFresnel(cosTheta, WATER_F0);

	// A reflectance floor: Schlick with water's f0 of 0.02 makes a calm
	// surface literally invisible when you look straight down at it. The
	// floor keeps a sheen on every pixel of water, and still reaches 1 at
	// grazing angles like the real term does.
	fresnel = max(fresnel, 0.12 + 0.08 * (1.0 - cosTheta));

#ifdef WATER_REFLECTION
	{
		vec3 reflectedDir = reflect(viewDir, normal);
		vec3 skyReflection = hzSkyReflection(reflectedDir);
		colour = mix(colour, skyReflection, fresnel);
	}
#else
	// Without the sky reflection pass the floor still has to show: a flat
	// ambient sheen stands in for the sky the surface would mirror.
	colour = mix(colour, hzAmbientColour() * (0.6 + 0.8 * skyLightLevel), fresnel * 0.5);
#endif

	// Shadow mapped specular highlight: the sun glint on the wave crests.
#if HZ_HAS_SUN || HZ_DIM_ID == 2
	{
		// Two lobes: a tight one for the glitter path and a broad one for the
		// soft sheen around it, which is what makes sunlight on water read as
		// sunlight on water.
		float specular = hzSpecular(normal, -viewDir, hzLightDir(), WATER_SHININESS)
			+ hzSpecular(normal, -viewDir, hzLightDir(), WATER_SHININESS * 0.22) * 0.30;
		colour += hzDirectLight() * (specular * 1.8 * shadow * hzSkyLightCurve(skyLightLevel));
	}
#endif

	//------------------------------------------------------- crest translucency --
	// Wave crests glow from inside when the light comes from behind them,
	// the way thin water always does.
	float crest = smoothstep(0.14, 0.34, hzWaterHeight(hzWorldPos(playerPos).xz));
	float crestBacklight = pow(clamp(dot(viewDir, hzLightDir()), 0.0, 1.0), 2.0);
	colour += crest * crestBacklight * vec3(0.10, 0.45, 0.42) * 0.55 * skyLightLevel;

	//---------------------------------------------------------------------- foam --
	float foam = tintData.a;
	colour = mix(colour, vec3(0.92, 0.96, 0.98) * surfaceLight, foam * 0.90);

	return hzApplyFog(colour, viewPos, playerPos);
}

//------------------------------------------------------------------------------

void main() {
	vec2 uv = hzUv;

	float depth = hzSceneDepth(uv);
	vec3 colour = hzSceneColour(uv);

	vec3 viewPos = hzViewPosFromUvDepth(uv, depth);
	vec3 playerPos = hzPlayerPosFromView(viewPos);

	vec4 waterData = texture2D(colortex3, uv);

	// z above zero marks a water pixel. The depth comparison makes sure that
	// nothing was drawn over the surface afterwards - the first person hand and
	// depth writing particles are rendered after the translucent terrain, and
	// those pixels belong to them, not to the water.
	if (waterData.z > 0.0 && abs(hzLinearDepth01(depth) - waterData.z) < 0.004) {
		colour = hzResolveWater(uv, colour, viewPos, playerPos, waterData,
		                        texture2D(colortex5, uv), depth);
	}

	// Underwater, lava and powder snow fog, applied to everything including the
	// sky. No-op while the camera is in air.
	colour = hzApplyMediaFog(colour, viewPos);

	gl_FragColor = vec4(colour, 1.0);
}

#endif // HZ_STAGE_FRAGMENT
