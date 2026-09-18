//==============================================================================
//
//   Horizon Shaders  -  post processing helpers (fragment stages only)
//
//   Bloom, the temporal filter and the tone mapping chain. Everything here runs
//   on the fullscreen post stages, which is why it may read colortex0..4 (Iris
//   only binds the real buffers there, not in the world programs).
//
//==============================================================================

#if !defined(HZ_POST_GLSL)
#define HZ_POST_GLSL

#include "/lib/composite_common.glsl"

// Everything below is fragment stage only. Iris compiles the full include graph
// once per stage, and the vertex stage of the post passes only runs
// hzCompositeVertex(), so the helpers (and the samplers they use) are kept out of
// it. Without this guard the vertex stage fails to compile because
// hzSceneColour and friends live inside the fragment block of
// lib/composite_common.glsl.
#if defined(HZ_STAGE_FRAGMENT)

uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;

//----------------------------------- bloom ------------------------------------

// Soft knee threshold: only the parts of the image brighter than the threshold
// are allowed to bleed, and the transition is smooth so that bright edges do not
// pop in and out of the bloom as the exposure changes.
vec3 hzBrightPass(vec3 colour) {
	float luma = hzLuminance(colour);
	float knee = BLOOM_THRESHOLD * 0.5 + HZ_EPS;
	float soft = hzClamp01((luma - BLOOM_THRESHOLD + knee) / (2.0 * knee));
	soft *= soft;

	float contribution = max(soft, luma - BLOOM_THRESHOLD) / max(luma, HZ_EPS);

	return colour * contribution;
}

// Separable gaussian blur. Five texture fetches with linear filtering give the
// same result as a nine tap box of weights 1 4 6 4 1 / 16.
// direction is the (already scaled) step in uv space.
vec3 hzBlurGaussian(sampler2D source, vec2 uv, vec2 direction) {
	vec3 sum = texture2D(source, uv).rgb * 0.2270270270;

	vec2 offset1 = direction * 1.3846153846;
	vec2 offset2 = direction * 3.2307692308;

	sum += (texture2D(source, uv + offset1).rgb + texture2D(source, uv - offset1).rgb) * 0.3162162162;
	sum += (texture2D(source, uv + offset2).rgb + texture2D(source, uv - offset2).rgb) * 0.0702702703;

	return sum;
}

//--------------------------------- temporal -----------------------------------

// Reprojects the current pixel into last frame's screen space using the depth
// buffer and the previous camera matrices Iris provides. Returns vec2(-1.0) when
// the pixel cannot be reprojected: sky pixels, or pixels that have just scrolled
// onto the screen.
vec2 hzReprojectUv(vec2 uv, float depth) {
	if (hzIsSky(depth)) {
		return vec2(-1.0);
	}

	vec3 viewPos = hzViewPosFromUvDepth(uv, depth);
	vec3 playerPos = hzPlayerPosFromView(viewPos);

	// Absolute world position, then into the previous frame's camera space.
	vec3 worldPos = hzWorldPos(playerPos);
	vec3 previousPlayerPos = worldPos - hzPrevWorldPos(vec3(0.0));
	vec3 previousViewPos = (gbufferPreviousModelView * vec4(previousPlayerPos, 1.0)).xyz;
	vec4 previousClip = gbufferPreviousProjection * vec4(previousViewPos, 1.0);

	if (previousClip.w <= 0.0) {
		return vec2(-1.0);
	}

	vec2 previousUv = (previousClip.xy / previousClip.w) * 0.5 + 0.5;

	if (previousUv.x < 0.0 || previousUv.x > 1.0 || previousUv.y < 0.0 || previousUv.y > 1.0) {
		return vec2(-1.0);
	}

	return previousUv;
}

// Blends the reprojected history with the current frame. A 3x3 min/max box of
// the current image clamps the history, which is what keeps the filter from
// smearing things the depth buffer cannot explain (mobs, particles, animated
// textures, water).
vec3 hzTemporalBlend(vec3 current, vec3 history, vec2 uv) {
	vec2 texel = hzTexel();

	vec3 minimum = current;
	vec3 maximum = current;

	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec3 tap = texture2D(colortex0, uv + vec2(float(x), float(y)) * texel).rgb;
			minimum = min(minimum, tap);
			maximum = max(maximum, tap);
		}
	}

	history = clamp(history, minimum, maximum);

	return mix(current, history, TEMPORAL_STRENGTH);
}

//------------------------------ tone map chain --------------------------------

// HDR scene colour plus bloom, mapped into displayable LDR and graded.
vec3 hzTonemapChain(vec3 colour, vec3 bloom) {
	colour *= EXPOSURE;

#ifdef BLOOM
	colour += bloom * BLOOM_STRENGTH;
#endif

	colour = hzTonemap(colour);
	colour = hzGrade(colour);

	return hzClamp01(colour);
}

// Display encoding: sRGB curve, optional vignette and a dither that breaks up
// banding in smooth gradients (sky, fog, water).
vec3 hzDisplayEncode(vec3 colour, vec2 uv, vec2 screenPos) {
#ifdef VIGNETTE
	colour *= hzVignetteFactor(uv);
#endif

	colour = hzLinearToSrgb(colour);

#ifdef DITHERING
	colour = hzDither(colour, screenPos);
#endif

	return hzClamp01(colour);
}

#endif // HZ_STAGE_FRAGMENT

#endif // HZ_POST_GLSL
