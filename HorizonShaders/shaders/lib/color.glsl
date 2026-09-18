//==============================================================================
//
//   Horizon Shaders  -  colour management
//
//   The whole pack works in linear light. Textures that Minecraft hands us are
//   sRGB encoded, so they are converted on read, and the final pass converts
//   back to sRGB for display.
//
//==============================================================================

#if !defined(HZ_COLOR_GLSL)
#define HZ_COLOR_GLSL

#include "/lib/common.glsl"

//--------------------------------- colour space -------------------------------

vec3 hzSrgbToLinear(vec3 color) {
	return pow(max(color, vec3(0.0)), vec3(2.2));
}

vec3 hzLinearToSrgb(vec3 color) {
	return pow(max(color, vec3(0.0)), vec3(1.0 / GAMMA));
}

float hzLuminance(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

//--------------------------------- tone mapping -------------------------------

vec3 hzTonemapReinhard(vec3 color) {
	const float white = 4.0;
	return (color * (1.0 + color / (white * white))) / (1.0 + color);
}

vec3 hzTonemapAces(vec3 color) {
	// Narkowicz' ACES filmic approximation.
	const float a = 2.51;
	const float b = 0.03;
	const float c = 2.43;
	const float d = 0.59;
	const float e = 0.14;
	return hzClamp01((color * (a * color + b)) / (color * (c * color + d) + e));
}

vec3 hzHablePartial(vec3 color) {
	const float a = 0.15;   // shoulder strength
	const float b = 0.50;   // linear strength
	const float c = 0.10;   // linear angle
	const float d = 0.20;   // toe strength
	const float e = 0.02;   // toe numerator
	const float f = 0.30;   // toe denominator
	return ((color * (a * color + c * b) + d * e) / (color * (a * color + b) + d * f)) - e / f;
}

vec3 hzTonemapHable(vec3 color) {
	const float white = 11.2;
	vec3 curve = hzHablePartial(color) / hzHablePartial(vec3(white));
	return hzClamp01(curve);
}

vec3 hzTonemap(vec3 color) {
	color = max(color, vec3(0.0));

#if TONEMAP_MODE == 0
	return hzTonemapReinhard(color);
#elif TONEMAP_MODE == 2
	return hzTonemapHable(color);
#else
	return hzTonemapAces(color);
#endif
}

//--------------------------------- colour grade -------------------------------

vec3 hzSaturation(vec3 color, float amount) {
	float luma = hzLuminance(color);
	return mix(vec3(luma), color, amount);
}

vec3 hzContrast(vec3 color, float amount) {
	return (color - 0.5) * amount + 0.5;
}

// Slightly stylised lift/gamma/gain grade, only active with COLOR_GRADING.
vec3 hzCreativeGrade(vec3 color) {
	const vec3 lift = vec3(0.012, 0.008, 0.026);   // cool shadows
	const vec3 gain = vec3(1.030, 1.000, 0.970);   // warm highlights
	color = color * gain + lift * (1.0 - hzClamp01(color));
	color = pow(max(color, vec3(0.0)), vec3(0.96, 1.0, 1.04));
	return color;
}

// LDR grade, applied after tone mapping. Exposure is an HDR operation and is
// applied to the scene colour before hzTonemap() instead.
vec3 hzGrade(vec3 color) {
#ifdef COLOR_GRADING
	color = hzCreativeGrade(color);
#endif

	// The house look: a pastel lift in the shadows (nothing ever goes black),
	// a whisper of gold in the highlights, then the user's saturation and
	// contrast on top. Deliberately constant - this is the pack's colour,
	// not an optional grade.
	color = color + vec3(0.012, 0.014, 0.024) * (1.0 - hzClamp01(color));
	color *= vec3(1.04, 1.00, 0.94);

	color = hzSaturation(color, SATURATION);
	color = hzContrast(color, CONTRAST);

	return max(color, vec3(0.0));
}

//----------------------------------- dither -----------------------------------

// Cheap blue-ish noise dither applied on the final, display encoded image.
vec3 hzDither(vec3 color, vec2 screenPos) {
	float noise = hzHash21(floor(screenPos) + 0.5) - 0.5;
	return color + noise / 255.0;
}

//---------------------------------- vignette ----------------------------------

float hzVignetteFactor(vec2 uv) {
	vec2 centered = (uv - 0.5) * vec2(1.0, 1.0);
	float distance = length(centered) * 1.41421356;
	return 1.0 - VIGNETTE_STRENGTH * smoothstep(0.55, 1.25, distance);
}

#endif // HZ_COLOR_GLSL
