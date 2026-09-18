//==============================================================================
//
//   Horizon Shaders  -  colour buffer layout
//
//   colortex0  RGBA16F  HDR linear scene colour. Written by the gbuffers
//                       programs, resolved by deferred, tonemapped by
//                       composite6, display encoded by final.
//   colortex1  RGBA16F  bloom buffer A
//   colortex2  RGBA16F  bloom buffer B
//   colortex3  RGBA16F  water buffer, part 1:
//                         x, y  surface normal in view space (z is rebuilt on
//                               decode, the sign is chosen from the view dir)
//                         z     linear depth of the surface, normalised by the
//                               far plane. Anything above zero marks a water
//                               pixel, which doubles as the mask.
//                         w     vanilla sky light level of the surface, 0..1
//   colortex4  RGBA16F  previous frame for the temporal filter (never cleared)
//   colortex5  RGBA8    water buffer, part 2:
//                         rgb   biome water tint, linear
//                         a     foam coverage
//
//   Iris binds colortex0..3 to a white pixel while the *world* programs run
//   (net.irisshaders.iris.samplers.IrisSamplers#addRenderTargetSamplers only
//   exposes colortex4 and up outside of fullscreen passes), so a gbuffers
//   program can write them through RENDERTARGETS but never sample them. All
//   sampling happens in deferred / composite / final, where the real buffers are
//   bound. That restriction is also why the water surface is resolved in
//   deferred: the untouched background colour is only available there, and
//   screen space refraction needs it.
//
//==============================================================================

#if !defined(HZ_BUFFERS_GLSL)
#define HZ_BUFFERS_GLSL

#define HZ_BUFFER_SCENE     0
#define HZ_BUFFER_BLOOM_A   1
#define HZ_BUFFER_BLOOM_B   2
#define HZ_BUFFER_WATER     3
#define HZ_BUFFER_HISTORY   4
#define HZ_BUFFER_WATER_TINT 5

//--------------------------- water buffer part 1 -------------------------------

// viewNormal  surface normal in view space
// depth01     hzLinearDepth01() of the surface, also used as the water mask
// skyLight    vanilla sky light level in 0..1
vec4 hzEncodeWaterNormal(vec3 viewNormal, float depth01, float skyLight) {
	return vec4(viewNormal.xy, depth01, skyLight);
}

// Rebuilds the view space normal. Water seen from above has a positive z, water
// seen from below (the camera is submerged) has to be flipped so that it always
// faces the viewer.
vec3 hzDecodeWaterNormal(vec2 encoded, vec3 viewDir) {
	float zSquared = max(0.0, 1.0 - dot(encoded, encoded));
	vec3 normal = normalize(vec3(encoded, sqrt(zSquared)));

	if (dot(normal, viewDir) > 0.0) {
		normal = -normal;
	}

	return normal;
}

#endif // HZ_BUFFERS_GLSL
