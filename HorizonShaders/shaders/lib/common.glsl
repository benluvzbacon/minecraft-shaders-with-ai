//==============================================================================
//
//   Horizon Shaders  -  shared uniforms, constants and math helpers
//
//   Included by every program of the pack (vertex and fragment stages). Only
//   uniforms that Iris 1.21.x actually provides are declared here, with the
//   exact types Iris registers them with (see net.irisshaders.iris.uniforms.*).
//
//==============================================================================

#if !defined(HZ_COMMON_GLSL)
#define HZ_COMMON_GLSL

#include "/lib/options.glsl"

//--------------------------------- constants ----------------------------------

#define HZ_PI      3.141592653589793
#define HZ_TAU     6.283185307179586
#define HZ_HALF_PI 1.5707963267948966
#define HZ_EPS     1e-5

// Minecraft "sea level" (the vanilla water surface height).
#define HZ_SEA_LEVEL 63.0

//----------------------------------- uniforms ---------------------------------
// Camera / viewport
uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;
uniform float near;
uniform float far;
uniform vec3 cameraPosition;
uniform ivec3 cameraPositionInt;
uniform vec3 cameraPositionFract;
uniform vec3 previousCameraPosition;
uniform ivec3 previousCameraPositionInt;
uniform vec3 previousCameraPositionFract;
uniform float eyeAltitude;
uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;

// Matrices. Iris (unlike OptiFine) names these without the "Matrix" suffix.
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

// Celestial bodies (view space directions, length 100)
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 shadowLightPosition;
uniform vec3 upPosition;
uniform float sunAngle;
uniform float shadowAngle;
uniform int moonPhase;

// Time
uniform int worldTime;
uniform int worldDay;
uniform float frameTimeCounter;

// Weather / world state
uniform float rainStrength;
uniform float wetness;
uniform float thunderStrength;
uniform vec3 skyColor;
uniform float ambientLight;
uniform float cloudHeight;
uniform bool hasSkylight;
uniform bool hasCeiling;
uniform int bedrockLevel;
uniform int heightLimit;
uniform int logicalHeightLimit;
uniform float temperature;
uniform float rainfall;

// Fog (stage dependent, Iris fills these for every program)
uniform vec3 fogColor;
uniform float fogStart;
uniform float fogEnd;
uniform float fogDensity;
uniform int fogMode;
uniform int fogShape;

// Player / camera state
uniform int isEyeInWater;
uniform float blindness;
uniform float nightVision;
uniform float screenBrightness;
uniform float playerMood;
uniform bool hideGUI;
uniform bool firstPersonCamera;
uniform bool isSpectator;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
uniform vec3 heldBlockLightColor;
uniform vec3 heldBlockLightColor2;
uniform int heldItemId;
uniform int heldItemId2;
uniform vec4 entityColor;
uniform int entityId;

//---------------------------------- helpers -----------------------------------

float hzClamp01(float value) {
	return clamp(value, 0.0, 1.0);
}

vec2 hzClamp01(vec2 value) {
	return clamp(value, 0.0, 1.0);
}

vec3 hzClamp01(vec3 value) {
	return clamp(value, 0.0, 1.0);
}

// Absolute (unshifted) world position. cameraPosition is shifted by Iris for
// precision reasons, cameraPositionInt + cameraPositionFract never is, which
// keeps animations from jumping when the shift happens.
vec3 hzWorldPos(vec3 playerPos) {
	return vec3(cameraPositionInt) + cameraPositionFract + playerPos;
}

vec3 hzPrevWorldPos(vec3 playerPos) {
	return vec3(previousCameraPositionInt) + previousCameraPositionFract + playerPos;
}

// View space direction of a pixel, from its screen uv and (optionally) depth.
vec3 hzViewPosFromUvDepth(vec2 uv, float depth) {
	vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	vec4 view = gbufferProjectionInverse * clip;
	return view.xyz / view.w;
}

// Same thing but for the far plane, used for sky pixels: returns a direction.
vec3 hzViewDirFromUv(vec2 uv) {
	vec4 clip = vec4(uv * 2.0 - 1.0, 1.0, 1.0);
	vec4 view = gbufferProjectionInverse * clip;
	return normalize(view.xyz);
}

vec3 hzPlayerPosFromView(vec3 viewPos) {
	return (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
}

// Camera relative world position of a pixel.
vec3 hzPlayerPosFromUvDepth(vec2 uv, float depth) {
	return hzPlayerPosFromView(hzViewPosFromUvDepth(uv, depth));
}

// Convert a view space direction into a world space direction (no translation,
// gbufferModelView only holds the camera rotation).
vec3 hzWorldDirFromView(vec3 viewDir) {
	return mat3(gbufferModelViewInverse) * viewDir;
}

vec3 hzViewDirFromWorld(vec3 worldDir) {
	return mat3(gbufferModelView) * worldDir;
}

// Distance from the camera along the view axis, in blocks. depth is the raw
// depth buffer value in [0, 1], near and far are the Iris uniforms of the same
// name (far is the render distance in blocks).
float hzLinearDepth(float depth) {
	float ndc = depth * 2.0 - 1.0;
	return (2.0 * near * far) / (far + near - ndc * (far - near));
}

// Same thing, normalised so that 1.0 is the far plane.
float hzLinearDepth01(float depth) {
	return hzLinearDepth(depth) / far;
}

//---------------------------------- noise -------------------------------------

float hzHash11(float value) {
	return fract(sin(value * 127.1) * 43758.5453123);
}

float hzHash21(vec2 value) {
	return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453123);
}

vec2 hzHash22(vec2 value) {
	value = vec2(dot(value, vec2(127.1, 311.7)), dot(value, vec2(269.5, 183.3)));
	return fract(sin(value) * 43758.5453123);
}

vec3 hzHash33(vec3 value) {
	value = vec3(dot(value, vec3(127.1, 311.7, 74.7)),
	             dot(value, vec3(269.5, 183.3, 246.1)),
	             dot(value, vec3(113.5, 271.9, 124.6)));
	return fract(sin(value) * 43758.5453123);
}

// Bilinear value noise, [0, 1].
float hzNoise2(vec2 uv) {
	vec2 grid = floor(uv);
	vec2 local = fract(uv);
	vec2 fade = local * local * (3.0 - 2.0 * local);

	float a = hzHash21(grid);
	float b = hzHash21(grid + vec2(1.0, 0.0));
	float c = hzHash21(grid + vec2(0.0, 1.0));
	float d = hzHash21(grid + vec2(1.0, 1.0));

	return mix(mix(a, b, fade.x), mix(c, d, fade.x), fade.y);
}

// Fractal brownian motion built on hzNoise2. The octave count is always a
// compile time constant so the loop can be unrolled by the driver.
float hzFbm2(vec2 uv, int octaves, float gain, float lacunarity) {
	float sum = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	float norm = 0.0;

	for (int i = 0; i < octaves; i++) {
		sum += amplitude * hzNoise2(uv * frequency);
		norm += amplitude;
		amplitude *= gain;
		frequency *= lacunarity;
	}

	return sum / max(norm, HZ_EPS);
}

float hzFbm2(vec2 uv, int octaves) {
	return hzFbm2(uv, octaves, 0.5, 2.0);
}

// Rotation helpers
mat2 hzRotate2(float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return mat2(c, -s, s, c);
}

mat3 hzRotateX(float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return mat3(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

#endif // HZ_COMMON_GLSL
