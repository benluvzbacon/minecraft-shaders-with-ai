//==============================================================================
//
//   Horizon Shaders  -  shared varyings and vertex boilerplate for the world
//
//   Both stages of every gbuffers_* program include this file, which is what
//   keeps the vertex outputs and the fragment inputs identical by construction.
//   The stage is selected with HZ_STAGE_VERTEX / HZ_STAGE_FRAGMENT, defined by
//   the .vsh / .fsh before the include.
//
//   The legacy built-ins used below (gl_Vertex, gl_Color, gl_Normal,
//   gl_MultiTexCoord0/1, gl_TextureMatrix[0/1], gl_NormalMatrix,
//   gl_ModelViewMatrix, ftransform) are all rewritten by Iris' compatibility
//   transformers, both for Sodium terrain and for vanilla render types, and
//   degrade to constants when a render type does not provide the attribute.
//
//==============================================================================

#if !defined(HZ_GBUFFERS_COMMON_GLSL)
#define HZ_GBUFFERS_COMMON_GLSL

#include "/lib/common.glsl"
#include "/lib/color.glsl"

//---------------------------------- varyings ----------------------------------

varying vec2 hzTexCoord;        // albedo atlas uv
varying vec2 hzLmCoord;        // lightmap uv, [1/32, 31/32]
varying vec4 hzVertexColour;   // biome tint * ambient occlusion
varying vec3 hzNormal;         // view space normal
varying vec3 hzViewPos;        // view space position
varying vec3 hzPlayerPos;      // camera relative world position
varying float hzViewDistance;  // distance to the camera in blocks
varying float hzBlockId;       // mc_Entity.x, only written by terrain programs

//----------------------------------- vertex -----------------------------------

#if defined(HZ_STAGE_VERTEX)

void hzVertexCommon() {
	gl_Position = ftransform();

	hzTexCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	hzLmCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	hzVertexColour = gl_Color;
	hzNormal = normalize(gl_NormalMatrix * gl_Normal);
	hzViewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
	hzPlayerPos = (gbufferModelViewInverse * vec4(hzViewPos, 1.0)).xyz;
	hzViewDistance = length(hzViewPos);
	hzBlockId = -1.0;
}

#endif

//---------------------------------- fragment ----------------------------------

#if defined(HZ_STAGE_FRAGMENT)

// Minecraft texture colours are sRGB encoded, the pack works in linear light.
// The alpha channel is kept as it is.
vec4 hzAlbedoFromTexture(vec4 textureColour) {
	return vec4(hzSrgbToLinear(textureColour.rgb), textureColour.a);
}

// Screen space uv of the fragment, needed to sample the depth textures that
// Iris copies for the translucent pass (a world program cannot read colortex0
// through colortex3, but depthtex1 is available and holds the depth of the
// scene before any translucent geometry was drawn).
vec2 hzScreenUv() {
	return gl_FragCoord.xy * vec2(1.0 / viewWidth, 1.0 / viewHeight);
}

#endif

#endif // HZ_GBUFFERS_COMMON_GLSL
