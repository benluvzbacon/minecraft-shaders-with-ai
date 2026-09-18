//==============================================================================
//
//   Horizon Shaders  -  gbuffers_basic
//
//   Untextured geometry: lines (the debug renderer, structure block outlines,
//   leashes when gbuffers_line is not provided) and coloured quads.
//
//   Iris' ProgramId table sends Line -> Basic, so omitting gbuffers_line means
//   lines end up here, which is the recommended way of handling them: the
//   program is then built through the compatibility path and Iris adds its own
//   line widening wrapper (it renames main() to irisMain(), runs it twice and
//   offsets the two endpoints by gl_Normal, which carries the other endpoint).
//
//   Render types that land here:
//     BASIC        POSITION       alpha test off
//     BASIC_COLOR  POSITION_COLOR alpha test "not zero"
//   Neither provides a normal, so gl_Normal degrades to vec3(0.0, 0.0, 1.0) -
//   a normal pointing at the camera, which is the only sensible default for a
//   line or a leash.
//
//==============================================================================

#include "/lib/gbuffers_common.glsl"
#include "/lib/lighting.glsl"

#if defined(HZ_STAGE_VERTEX)

void main() {
	hzVertexCommon();
}

#endif // HZ_STAGE_VERTEX

#if defined(HZ_STAGE_FRAGMENT)

void main() {
	vec4 vertexColour = hzVertexColour;

	// There is no texture to sample, the vertex colour is the albedo.
	vec3 albedo = hzSrgbToLinear(vertexColour.rgb);

	vec3 colour = hzShadeSurface(albedo, hzNormal, hzViewPos, hzPlayerPos,
	                             hzLmCoord, 0.0);

	// BASIC_COLOR is given a "discard when alpha is zero" test by Iris, so the
	// alpha written here has to be the real one.
	gl_FragColor = vec4(colour, vertexColour.a);
}

#endif // HZ_STAGE_FRAGMENT
