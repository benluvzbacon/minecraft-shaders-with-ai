//==============================================================================
//
//   Horizon Shaders  -  shadow map sampling (fragment stages only)
//
//   Iris binds these samplers for every world, composite, deferred and final
//   program that declares them:
//     shadowtex0   depth of the shadow pass, including translucent geometry
//     shadowtex1   depth of the shadow pass, opaque geometry only ("shadow")
//     shadowcolor0 colour written by shadow.fsh, cleared to vec4(1.0)
//   Filtering is bilinear by default, so every tap below is already a small
//   2x2 average on top of the Poisson disk.
//
//==============================================================================

#if !defined(HZ_SHADOWS_GLSL)
#define HZ_SHADOWS_GLSL

#include "/lib/shadow_math.glsl"

uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;

// 16 point Poisson disk, used for the percentage closer filter.
const vec2 HZ_POISSON[16] = vec2[16](
	vec2(-0.94201624, -0.39906216),
	vec2( 0.94558609, -0.76890725),
	vec2(-0.09418410, -0.92938870),
	vec2( 0.34495938,  0.29387760),
	vec2(-0.91588581,  0.45771432),
	vec2(-0.81544232, -0.87912464),
	vec2(-0.38277543,  0.27676845),
	vec2( 0.97484398,  0.75648379),
	vec2( 0.44323325, -0.97511554),
	vec2( 0.53742981, -0.47373420),
	vec2(-0.26496911, -0.41893023),
	vec2( 0.79197514,  0.19090188),
	vec2(-0.24188840,  0.99706507),
	vec2(-0.81409955,  0.91437590),
	vec2( 0.19984126,  0.78641367),
	vec2( 0.14383161, -0.14100790)
);

// How much light reaches a surface: vec3(1.0) is fully lit, vec3(0.0) is fully
// shadowed, anything in between is either a soft shadow edge or light that was
// tinted while passing through translucent geometry.
// playerPos  - camera relative world position of the shaded point
// viewNormal - surface normal in view space
vec3 hzShadowAt(vec3 playerPos, vec3 viewNormal) {
	vec3 noShadow = vec3(1.0);

#ifndef SHADOWS
	return noShadow;
#endif

#if !HZ_HAS_SHADOWS
	return noShadow;
#endif

	float distortion = 1.0;
	vec3 uvDepth = hzShadowUvDepth(playerPos, viewNormal, distortion);

	// Outside of the shadow map: treat the pixel as lit.
	if (uvDepth.x < 0.0) {
		return noShadow;
	}

	// Fade shadows out towards the configured shadow distance so that the edge
	// of the map never shows up as a hard line in the world.
	float radial = length(playerPos) / SHADOW_DISTANCE;
	float fade = 1.0 - smoothstep(0.72, 1.0, radial);
	if (fade <= 0.0) {
		return noShadow;
	}

	float bias = hzShadowBias(distortion);
	float receiverDepth = uvDepth.z - bias;

	// Rotate the kernel per pixel to break up the regular disk pattern.
	// gl_FragCoord only exists in the fragment stage, and this function has to
	// compile in both stages because Iris compiles the whole include graph once
	// per stage, so the vertex stage gets a world space seed instead. It never
	// samples shadows, the alternative is only there to keep it valid.
#if defined(HZ_STAGE_FRAGMENT)
	mat2 rotation = hzRotate2(hzHash21(gl_FragCoord.xy) * HZ_TAU);
#else
	mat2 rotation = hzRotate2(hzHash21(playerPos.xz * 4.0) * HZ_TAU);
#endif
	float radius = hzShadowRadius(distortion);

	float litOpaque = 0.0;

#ifdef SOFT_SHADOWS
	for (int i = 0; i < SHADOW_SAMPLES; i++) {
		vec2 offset = rotation * HZ_POISSON[i] * radius;
		float occluderDepth = texture2D(shadowtex1, uvDepth.xy + offset).r;
		litOpaque += step(receiverDepth, occluderDepth);
	}
	litOpaque /= float(SHADOW_SAMPLES);
#else
	litOpaque = step(receiverDepth, texture2D(shadowtex1, uvDepth.xy).r);
#endif

	vec3 tint = vec3(0.0);

#ifdef COLORED_SHADOWS
	// shadowtex1 ignores translucent geometry, shadowtex0 does not. When the
	// closest occluder is translucent the recorded transmission colour is used
	// instead of a hard shadow, which is what gives stained glass and water
	// coloured shadows.
	float translucentDepth = texture2D(shadowtex0, uvDepth.xy).r;
	float opaqueDepth = texture2D(shadowtex1, uvDepth.xy).r;

	if (receiverDepth > opaqueDepth) {
		tint = vec3(0.0);
	} else if (receiverDepth > translucentDepth) {
		vec4 transmission = texture2D(shadowcolor0, uvDepth.xy);
		tint = transmission.rgb * transmission.a;
	} else {
		tint = vec3(1.0);
	}
#endif

	vec3 shadow = mix(tint, vec3(1.0), litOpaque);

	return mix(noShadow, shadow, fade);
}

#endif // HZ_SHADOWS_GLSL
