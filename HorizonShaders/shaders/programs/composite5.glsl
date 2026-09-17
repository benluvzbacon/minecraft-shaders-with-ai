//==============================================================================
//
//   Horizon Shaders  -  composite5
//
//   Temporal smoothing (the TEMPORAL_SMOOTHING option, off by default).
//
//   The pixel is reprojected into last frame's screen space with the depth buffer
//   and the previous camera matrices that Iris provides, the history is clamped to
//   a 3x3 neighbourhood of the current image and then blended. The clamp is what
//   keeps the filter honest: anything the depth buffer cannot explain - mobs,
//   particles, animated textures, the water surface - is rejected instead of
//   smeared.
//
//   This is a temporal anti flicker filter rather than full TAA. Iris does not
//   expose sub pixel projection jitter, so there is no new information to
//   reconstruct and no sharpening step; what it does remove is the shimmer of
//   thin geometry, wave crests and shadow edges.
//
//   colortex4 is never cleared (const bool colortex4Clear = false in
//   lib/consts.glsl), which is what makes it a history buffer. The pass writes
//   the same value to the scene buffer and to the history.
//
//==============================================================================

#include "/lib/composite_common.glsl"
#include "/lib/post.glsl"

#if defined(HZ_STAGE_VERTEX)

void main() {
	hzCompositeVertex();
}

#endif // HZ_STAGE_VERTEX

#if defined(HZ_STAGE_FRAGMENT)

/* RENDERTARGETS:0,4 */

void main() {
	vec2 uv = hzUv;

	vec3 colour = hzSceneColour(uv);

#ifdef TEMPORAL_SMOOTHING
	float depth = hzSceneDepth(uv);

	vec2 previousUv = hzReprojectUv(uv, depth);
	vec3 history = previousUv.x >= 0.0 ? texture2D(colortex4, previousUv).rgb : colour;

	colour = hzTemporalBlend(colour, history, uv);
#endif

	// Without the option the pass degenerates to a copy of the scene buffer, and
	// shaders.properties removes it from the program set entirely
	// (program.composite5.enabled=TEMPORAL_SMOOTHING). The guard is still here so
	// that Iris sees the option: a boolean option is only registered as a
	// configurable one when some source references it through #ifdef or #ifndef
	// (OptionAnnotatedSource#parseIfdef).
	gl_FragData[0] = vec4(colour, 1.0);
	gl_FragData[1] = vec4(colour, 1.0);
}

#endif // HZ_STAGE_FRAGMENT
