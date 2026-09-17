//==============================================================================
//
//   Horizon Shaders  -  gbuffers_skybasic
//
//   The sky. Two render types end up here:
//     SKY_BASIC        POSITION       the sky box, alpha test off, fullbright
//     SKY_BASIC_COLOR  POSITION_COLOR the sunrise/sunset quad and the dark sky
//                                     plane, alpha test "not zero"
//   The vanilla sun, moon, stars and cloud layer are switched off in
//   shaders.properties, so this program is the only source of sky: gradient,
//   stars, sun disc, moon disc with phases and the procedural cloud layer are
//   all drawn here from the view direction.
//
//   The alpha written below is 0.0 on purpose, and it is what keeps the two
//   render types apart without the pack having to guess:
//     - the sky box has no alpha test, so it is written normally and covers the
//       screen with the procedural sky;
//     - every coloured sky quad gets Iris' NON_ZERO_ALPHA test, which discards
//       the fragment outright. The sunrise quad is redundant (the procedural
//       gradient already contains the sunset colours) and discarding it is
//       correct no matter whether vanilla blends it alpha-wise or additively.
//   colortex0's alpha channel is not read anywhere in this pack, so writing 0
//   for the sky box costs nothing.
//
//==============================================================================

#include "/lib/gbuffers_common.glsl"
#include "/lib/sky.glsl"

#if defined(HZ_STAGE_VERTEX)

void main() {
	hzVertexCommon();
}

#endif // HZ_STAGE_VERTEX

#if defined(HZ_STAGE_FRAGMENT)

void main() {
	// The sky box surrounds the camera, so its view space position is the view
	// direction of the pixel, whatever size vanilla builds the box at.
	vec3 viewDir = normalize(hzViewPos);

	vec3 colour = hzSky(viewDir);

	// Brightness and blindness affect the sky like everything else.
	colour *= 1.0 + nightVision * 2.2;
	colour *= mix(1.0, 0.02, blindness);

	gl_FragColor = vec4(colour, 0.0);
}

#endif // HZ_STAGE_FRAGMENT
