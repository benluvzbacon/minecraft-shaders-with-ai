//==============================================================================
//
//   Horizon Shaders  -  gbuffers_textured (Nether, vertex stage)
//
//   GENERATED FILE, do not edit. tools/generate_programs.py writes this wrapper.
//   The program itself lives in shaders/programs/gbuffers_textured.glsl and is shared by the
//   Overworld, the Nether (world-1) and the End (world1); lib/dimension.glsl
//   switches behaviour on the define below.
//
//   Iris does not merge a dimension folder with the pack root
//   (ShaderPack#getProgramSet), so each folder has to contain every program that
//   should be active in that dimension.
//
//==============================================================================
#version 330 compatibility

// Telling lib/dimension.glsl which dimension this is.
#define DIM_NETHER
#define HZ_STAGE_VERTEX
#include "/programs/gbuffers_textured.glsl"
