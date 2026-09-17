//==============================================================================
//
//   Horizon Shaders  -  gbuffers_water
//
//   All translucent terrain: water, lava* , ice, glass, stained glass, slime
//   blocks, honey blocks. TERRAIN_TRANSLUCENT is the only render type that maps
//   to ProgramId.Water, and it is rendered with IrisVertexFormats.TERRAIN, so the
//   block material id from block.properties is available here.
//
//   Water itself is *not* shaded in this program. Iris binds colortex0..3 to a
//   white pixel while world programs run (IrisSamplers#addRenderTargetSamplers
//   only exposes colortex4 and up outside fullscreen passes), so the background
//   colour a refracted ray would need simply is not readable here. Instead this
//   program fills a small material buffer and leaves the scene colour alone:
//
//     colortex0  vec4(0.0) - with the vanilla translucent blend state
//                (SRC_ALPHA, ONE_MINUS_SRC_ALPHA) an alpha of zero is a no-op,
//                while the depth buffer still records the surface position.
//     colortex3  view space normal, surface depth and sky light level
//     colortex5  biome water tint and foam coverage
//
//   deferred then resolves the surface: it refracts the untouched background,
//   applies Beer-Lambert absorption over the water depth, adds the body colour,
//   the Fresnel weighted sky reflection, the shadow mapped sun highlight and the
//   foam. Everything else that goes through this program is shaded the ordinary
//   way and blended over the scene right here.
//
//   * Lava is not translucent in vanilla - it is rendered as solid terrain and
//     therefore shaded by gbuffers_terrain, which also treats it as emissive.
//
//==============================================================================

#include "/lib/gbuffers_common.glsl"
#include "/lib/lighting.glsl"
#include "/lib/material.glsl"
#include "/lib/water.glsl"
#include "/lib/buffers.glsl"

#if defined(HZ_STAGE_VERTEX)

attribute vec4 mc_Entity;

void main() {
	hzVertexCommon();

	hzBlockId = mc_Entity.x;
}

#endif // HZ_STAGE_VERTEX

#if defined(HZ_STAGE_FRAGMENT)

/* RENDERTARGETS:0,3,5 */

uniform sampler2D gtexture;
uniform sampler2D depthtex1;

void main() {
	vec2 screenUv = hzScreenUv();
	vec4 textureColour = texture2D(gtexture, hzTexCoord) * hzVertexColour;

	//--------------------------------------------------------------------------
	// Everything that is not water: ice, glass, stained glass, slime, honey.
	//--------------------------------------------------------------------------
	if (!hzIsWater(hzBlockId)) {
		vec4 albedo = hzAlbedoFromTexture(textureColour);

		vec3 colour = hzShadeSurface(albedo.rgb, hzNormal, hzViewPos, hzPlayerPos,
		                             hzLmCoord, hzEmissive(hzBlockId));

		gl_FragData[0] = vec4(colour, textureColour.a);
		gl_FragData[1] = vec4(0.0);
		gl_FragData[2] = vec4(0.0);

		return;
	}

	//--------------------------------------------------------------------------
	// Water: fill the material buffer, leave the scene colour untouched.
	//--------------------------------------------------------------------------

	// depthtex1 is the copy Iris takes of the depth buffer before any translucent
	// geometry is drawn, so the difference to this fragment is the amount of
	// water between the eye and whatever is behind it.
	float backgroundDepth = texture2D(depthtex1, screenUv).r;
	float waterDepth = max(hzLinearDepth(backgroundDepth) - hzLinearDepth(gl_FragCoord.z), 0.0);

	// The wave field is evaluated in absolute world space, so the surface does
	// not swim when the camera moves.
	vec2 worldXZ = hzWorldPos(hzPlayerPos).xz;
	vec2 gradient = hzWaterGradient(worldXZ, hzViewDistance);
	vec3 worldNormal = hzWaterWorldNormal(gradient, WATER_WAVE_STRENGTH);
	vec3 viewNormal = normalize(hzViewDirFromWorld(worldNormal));

	// Vanilla tints water per biome through the vertex colour; keep it, it is
	// what makes swamp and cold ocean water read differently.
	vec3 tint = hzSrgbToLinear(textureColour.rgb);

	float foam = hzFoam(waterDepth, hzWaterHeight(worldXZ));
	float surfaceDepth = hzLinearDepth01(gl_FragCoord.z);
	float skyLight = hzLightLevels(hzLmCoord).y;

	gl_FragData[0] = vec4(0.0);
	gl_FragData[1] = hzEncodeWaterNormal(viewNormal, surfaceDepth, skyLight);
	gl_FragData[2] = vec4(tint, foam);
}

#endif // HZ_STAGE_FRAGMENT
