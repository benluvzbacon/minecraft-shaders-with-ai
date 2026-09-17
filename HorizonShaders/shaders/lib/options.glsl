//==============================================================================
//
//   Horizon Shaders  -  user configurable options
//
//   Every `#define` below is a real Iris shader option. Iris rewrites this file
//   when you change something in the in-game shader settings menu, so the menu
//   is the intended way of editing these values.
//
//   Format rules (enforced by Iris' OptionAnnotatedSource parser):
//     boolean option, enabled   ->  #define NAME
//     boolean option, disabled  ->  //#define NAME
//     value option              ->  #define NAME value //[value1 value2 ...]
//   The default value of a value option must appear verbatim in its list.
//
//==============================================================================

#if !defined(HZ_OPTIONS_GLSL)
#define HZ_OPTIONS_GLSL

//=================================< SHADOWS >==================================

// Real shadow mapping (a depth-only pass rendered from the sun/moon).
#define SHADOWS

// Percentage closer filtering, softens shadow edges.
#define SOFT_SHADOWS

// Let stained glass / water / leaves tint the light that passes through them.
#define COLORED_SHADOWS

#define SHADOW_RESOLUTION 2048     //[512 1024 2048 4096 8192]
#define SHADOW_DISTANCE 128.0      //[48.0 64.0 96.0 128.0 160.0 192.0 256.0 320.0]
#define SHADOW_SOFTNESS 1.0        //[0.5 0.75 1.0 1.5 2.0 3.0]
#define SHADOW_SAMPLES 12          //[4 8 12 16]
#define SHADOW_BIAS 0.6            //[0.2 0.35 0.6 1.0 1.5 2.5]
#define SHADOW_DISTORTION 0.6      //[0.0 0.2 0.4 0.6 0.8 1.0]
#define SUN_PATH_TILT -22.0        //[-40.0 -30.0 -22.0 -12.0 0.0 12.0 22.0 30.0 40.0]

//=================================< LIGHTING >=================================

#define SUNLIGHT_STRENGTH 1.0      //[0.5 0.7 1.0 1.3 1.6 2.0]
#define MOONLIGHT_STRENGTH 1.0     //[0.25 0.5 1.0 1.5 2.0]
#define AMBIENT_STRENGTH 1.0       //[0.5 0.7 1.0 1.3 1.6 2.0]
#define BLOCKLIGHT_STRENGTH 1.0    //[0.5 0.7 1.0 1.3 1.6 2.0]
#define BLOCKLIGHT_FALLOFF 2.4     //[1.6 2.0 2.4 3.0 4.0]

// Extra light emitted by the item held in the player hands.
#define HAND_LIGHT

// Sky light leaking into caves based on the eye brightness uniform.
#define CAVE_ADAPT

//=================================< ATMOSPHERE >===============================

// Shader side cloud layer (vanilla clouds are disabled in shaders.properties).
#define CLOUDS

#define CLOUD_QUALITY 1            //[0 1 2]
#define CLOUD_DENSITY 0.55         //[0.25 0.40 0.55 0.70 0.85]
#define CLOUD_ALTITUDE 128.0       //[96.0 128.0 160.0 192.0 256.0]
#define CLOUD_SPEED 1.0            //[0.0 0.5 1.0 2.0 4.0]

#define STARS
#define STAR_DENSITY 1.0           //[0.5 1.0 1.5 2.0]

// Extra fog at the very edge of the render distance, hides pop-in.
#define BORDER_FOG

#define FOG_DENSITY 1.0            //[0.5 0.75 1.0 1.5 2.0]
#define UNDERWATER_DENSITY 1.0     //[0.5 0.75 1.0 1.5 2.0]

//=================================< WATER >====================================

#define WATER_QUALITY 1            //[0 1 2]
#define WATER_WAVES
#define WATER_WAVE_STRENGTH 1.0    //[0.0 0.5 1.0 1.5 2.0]
#define WATER_REFRACTION
#define WATER_REFLECTION
#define WATER_ABSORPTION 1.0       //[0.5 0.75 1.0 1.5 2.0]
#define WATER_TURBIDITY 0.35       //[0.15 0.25 0.35 0.50 0.75]
#define WATER_SHININESS 96.0       //[32.0 64.0 96.0 160.0 256.0]
#define WATER_F0 0.02              //[0.02 0.04 0.08]
#define WATER_FOAM

//=================================< POST PROCESSING >==========================

#define BLOOM
#define BLOOM_STRENGTH 0.16        //[0.04 0.08 0.16 0.25 0.40]
#define BLOOM_QUALITY 1            //[0 1 2]
#define BLOOM_THRESHOLD 1.0        //[0.6 0.8 1.0 1.4 2.0]

#define TONEMAP_MODE 1             //[0 1 2]
#define EXPOSURE 1.0               //[0.5 0.7 1.0 1.3 1.7 2.2]
#define SATURATION 1.05            //[0.8 0.9 1.0 1.05 1.15 1.3]
#define CONTRAST 1.0               //[0.9 0.95 1.0 1.05 1.1 1.2]
#define GAMMA 2.2                  //[1.8 2.0 2.2 2.4]

#define VIGNETTE
#define VIGNETTE_STRENGTH 0.25     //[0.10 0.25 0.40 0.60]

// Subtle colour grade (lift/gamma/gain tint), off by default.
//#define COLOR_GRADING

// Temporal upscaling-free anti flicker filter, needs a reprojection pass.
//#define TEMPORAL_SMOOTHING
#define TEMPORAL_STRENGTH 0.65     //[0.40 0.55 0.65 0.80 0.90]

#define DITHERING

//==============================================================================
//  Derived (non option) values. These have no allowed-value comment on purpose,
//  so Iris does not turn them into menu entries.
//==============================================================================

// ---- quality presets mapped from the *_QUALITY options -----------------------
#if WATER_QUALITY == 0
	#define WATER_WAVE_COUNT 3
#elif WATER_QUALITY == 1
	#define WATER_WAVE_COUNT 5
#else
	#define WATER_WAVE_COUNT 8
#endif

#if CLOUD_QUALITY == 0
	#define CLOUD_STEPS 8
	#define CLOUD_OCTAVES 3
#elif CLOUD_QUALITY == 1
	#define CLOUD_STEPS 14
	#define CLOUD_OCTAVES 4
#else
	#define CLOUD_STEPS 22
	#define CLOUD_OCTAVES 5
#endif

#if BLOOM_QUALITY == 0
	#define BLOOM_RADIUS 1.0
	#define BLOOM_WIDE 0
#elif BLOOM_QUALITY == 1
	#define BLOOM_RADIUS 2.0
	#define BLOOM_WIDE 1
#else
	#define BLOOM_RADIUS 3.0
	#define BLOOM_WIDE 1
#endif

#endif // HZ_OPTIONS_GLSL
