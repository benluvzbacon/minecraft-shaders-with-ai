//==============================================================================
//
//   Horizon Shaders  -  shadow map maths
//
//   This file contains *only* the projection helpers, no samplers, so it can be
//   included by shadow.vsh (which renders the map) as well as by the lighting
//   code (which reads it). Both sides must agree on the distortion, otherwise
//   the shadows do not line up with the geometry that casts them.
//
//   Iris renders the shadow pass with an orthographic projection covering
//   +/- shadowDistance blocks around the camera, and shadowModelView is already
//   camera relative and snapped to shadowIntervalSize, so a camera relative
//   "player space" position can be fed straight into it.
//
//==============================================================================

#if !defined(HZ_SHADOW_MATH_GLSL)
#define HZ_SHADOW_MATH_GLSL

#include "/lib/common.glsl"

// Iris builds the shadow ortho matrix with near = -100.05 and far = 156 by
// default, i.e. 256.05 blocks of depth are mapped onto the [0, 1] range of the
// depth texture. This converts a bias expressed in blocks into depth units.
#define HZ_SHADOW_DEPTH_RANGE 256.05
#define HZ_SHADOW_TEXEL (2.0 * SHADOW_DISTANCE / float(SHADOW_RESOLUTION))

// Radial distortion factor: 1.0 in the middle of the shadow map, larger towards
// its border. Dividing the shadow space position by it buys resolution close to
// the camera at the cost of resolution far away.
float hzShadowDistortion(vec3 shadowViewPos) {
	float radial = length(shadowViewPos.xy) / SHADOW_DISTANCE;
	return 1.0 + SHADOW_DISTORTION * radial * 2.0;
}

// playerPos: camera relative world position, viewNormal: normal in view space.
// Returns vec3(shadowU, shadowV, shadowDepth) or vec3(-1.0) when the sample
// falls outside of the shadow map.
vec3 hzShadowUvDepth(vec3 playerPos, vec3 viewNormal, out float distortionOut) {
	// Offset the sample along the normal by roughly one shadow texel to avoid
	// self shadowing ("shadow acne") on surfaces facing away from the light.
	vec3 shadowView = (shadowModelView * vec4(playerPos, 1.0)).xyz;
	float distortion = hzShadowDistortion(shadowView);

	vec3 worldNormal = mat3(gbufferModelViewInverse) * viewNormal;
	vec3 offsetPos = playerPos + worldNormal * (HZ_SHADOW_TEXEL * distortion * 1.6);

	shadowView = (shadowModelView * vec4(offsetPos, 1.0)).xyz;
	distortion = hzShadowDistortion(shadowView);

	// Only the xy components are scaled, that way the depth precision of the
	// map stays untouched while both the writer and the reader agree on it.
	shadowView.xy /= distortion;

	vec4 clip = shadowProjection * vec4(shadowView, 1.0);
	vec3 ndc = clip.xyz / clip.w;
	vec3 uvDepth = ndc * 0.5 + 0.5;

	distortionOut = distortion;

	if (uvDepth.x < 0.0 || uvDepth.x > 1.0 ||
	    uvDepth.y < 0.0 || uvDepth.y > 1.0 ||
	    uvDepth.z < 0.0 || uvDepth.z > 1.0) {
		return vec3(-1.0);
	}

	return uvDepth;
}

// Depth bias, in depth texture units, scaled by the local distortion so that it
// stays proportional to the (growing) texel size.
float hzShadowBias(float distortion) {
	return SHADOW_BIAS * 0.09 * distortion * (2.0 / HZ_SHADOW_DEPTH_RANGE);
}

// PCF radius in shadow map uv units. One shadow texel is 1/shadowMapResolution
// of the map, but because the position is divided by the distortion factor the
// world space footprint of a texel grows with it, so the uv radius has to grow
// by the same amount to keep the filter width constant in world space.
float hzShadowRadius(float distortion) {
	return SHADOW_SOFTNESS * distortion * (2.0 / float(SHADOW_RESOLUTION));
}

#endif // HZ_SHADOW_MATH_GLSL
