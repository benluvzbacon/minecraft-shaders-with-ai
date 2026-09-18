//==============================================================================
//
//   Horizon Shaders  -  gbuffers_entities
//
//   Mobs, players, armour stands, and - through the fallback chain - item
//   entities, glowing outlines and the text of signs held by entities.
//   ENTITIES_SOLID / ENTITIES_CUTOUT / ENTITIES_ALPHA / ENTITIES_TRANSLUCENT /
//   ENTITIES_GLOWING all resolve here.
//
//   Two things are special about the entity render types:
//
//   1. Their vertex format carries an overlay coordinate. Iris'
//      EntityPatcher#patchOverlayColor deletes a plain "uniform vec4
//      entityColor;" declaration and replaces it with a varying that holds the
//      overlay lookup: rgb is the tint, a is how strongly it applies. That is
//      how the hurt flash, the freezing overlay and similar effects reach the
//      pack, so the tint is mixed in below. For formats without an overlay the
//      declaration stays a uniform, which Iris fills with vec4(0.0) - a no-op.
//
//   2. ENTITIES_ALPHA gets Iris' VERTEX_ALPHA test, which discards unless the
//      fragment alpha is *strictly* greater than the vertex alpha. Vanilla only
//      requires "not less than", so an opaque entity drawn with an opaque vertex
//      colour would vanish entirely. Nudging opaque fragments by 0.0039 keeps
//      them visible and is far below anything the alpha blend can show.
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

uniform sampler2D gtexture;

void main() {
	vec4 textureColour = texture2D(gtexture, hzTexCoord) * hzVertexColour;
	vec4 albedo = hzAlbedoFromTexture(textureColour);

	albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);

	vec3 colour = hzShadeSurface(albedo.rgb, hzNormal, hzViewPos, hzPlayerPos,
	                             hzLmCoord, 0.0);

	float alpha = textureColour.a;
	alpha = alpha > 0.5 ? alpha + 0.0039 : alpha;

	gl_FragColor = vec4(colour, alpha);
}

#endif // HZ_STAGE_FRAGMENT
