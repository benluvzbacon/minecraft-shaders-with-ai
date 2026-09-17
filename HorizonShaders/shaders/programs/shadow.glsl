//==============================================================================
//
//   Horizon Shaders  -  shadow map pass
//
//   Iris renders this program for every shadow caster (terrain, entities,
//   block entities, translucent geometry) from the light's point of view. The
//   depth attachment becomes shadowtex0 (all casters) and, copied just before
//   the translucent part of the pass, shadowtex1 (opaque casters only). The
//   colour written here lands in shadowcolor0 and is read back by hzShadowAt()
//   as the light transmission colour, which is what lets stained glass, water
//   and leaves cast coloured shadows.
//
//   The RENDERTARGETS directive is there on purpose: without one, Iris attaches
//   both shadowcolor0 and shadowcolor1 to the shadow framebuffer
//   (IrisRenderingPipeline#createShadowShader uses {0, 1} when the draw buffers
//   are unknown), which would allocate a second full resolution buffer that the
//   pack never reads.
//
//==============================================================================

#include "/lib/color.glsl"
#include "/lib/material.glsl"

varying vec2 hzShadowTexCoord;
varying vec4 hzShadowVertexColour;

#if defined(HZ_STAGE_VERTEX)

attribute vec4 mc_Entity;

void main() {
	// The shadow pass projection is set up by Iris (shadowProjection and
	// shadowModelView already contain the sun path rotation, the distortion and
	// the interval snapping), so the plain fixed function transform is exactly
	// what is wanted here.
	// Same sway as the terrain pass, or swaying leaves would leave their
	// shadows behind. gl_Vertex is read only, hence the local copy.
	vec4 vertex = gl_Vertex;
	vertex.xyz += hzFoliageSway(vertex.xyz + cameraPosition, mc_Entity.x);

	gl_Position = gl_ModelViewProjectionMatrix * vertex;

	hzShadowTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	hzShadowVertexColour = gl_Color;
}

#endif // HZ_STAGE_VERTEX

#if defined(HZ_STAGE_FRAGMENT)

/* RENDERTARGETS:0 */

uniform sampler2D gtexture;

void main() {
	vec4 textureColour = texture2D(gtexture, hzShadowTexCoord);

	// rgb is the transmission colour of the caster, stored in linear light.
	// a has to stay the real alpha (texture alpha times vertex alpha): Iris
	// appends the alpha test of the current render type - ONE_TENTH for cutout
	// terrain and cutout entities - and that test is what punches holes for
	// leaves, glass panes, fences and mobs.
	gl_FragColor = vec4(
		hzSrgbToLinear(textureColour.rgb * hzShadowVertexColour.rgb),
		textureColour.a * hzShadowVertexColour.a
	);
}

#endif // HZ_STAGE_FRAGMENT
