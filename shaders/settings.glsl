#ifndef SETTINGS_GLSL
    #define SETTINGS_GLSL a

    #define COLORED_SHADOW

    #define PT_BOUNCES 2 // [1 2 3 4]
    #define PT_SAMPLES 1 // [1 2 3 4]
    
    #define MAX_QUADS 262144 // [65536 131072 262144 524288]

    #define BLOOM
    #define BLOOM_STRENGTH 0.1 // [0.0 0.02 0.05 0.1 0.15 0.2 0.3 0.5]

    #define WAVE_SCALE 0.004
    #define WAVE_SPEED 0.0067
    #define WAVE_HEIGHT 1.5
    #define WAVE_PARALLAX_STRENGTH 0.7
    #define WAVE_OCTAVES 6

    #define WATER_FOG_DENSITY 1.0
    #define WATER_FOG_SCATTERING 0.03

    #define CAUSTICS_MAP_RES 512
    #define CAUSTICS_MAP_BLOCKS 128.0

    #define GTAO_ENABLED
    #define GTAO_SLICE_COUNT 2 // [1 2 3 4 5 6 8]
    #define GTAO_DIRECTION_SAMPLE_COUNT 6 // [2 3 4 5 6 8 10 12 16]
    #define GTAO_SEARCH_RADIUS 1.5 // [0.25 0.5 0.75 1.0 1.5 2.0 2.5 3.0 4.0 6.0]
    #define GTAO_INTENSITY 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0 2.5 3.0]

    #define PUDDLES_ENABLED
    #define PUDDLES_AMOUNT 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5]

    #define SKYLIGHT_CURVE 6.0 // [3.0 4.0 5.0 6.0 8.0 10.0 12.0]

    #define TAA_ENABLED
    #define TAA_BLENDWEIGHT 0.90 // [0.50 0.60 0.70 0.75 0.80 0.85 0.88 0.90 0.92 0.94 0.96 0.98]
    #define TAA_AGGRESSION 0.50  // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
    
    //#define TAAU_ENABLED
    #define TAAU_RENDER_SCALE 0.75 // [0.50 0.60 0.67 0.75 0.85 1.00]

    #define EXPOSURE_MIN -2.0 // [-5.0 -4.0 -3.0 -2.5 -2.0 -1.5 -1.0 -0.5 0.0]
    #define EXPOSURE_MAX 2.0 // [0.0 0.5 1.0 1.5 2.0 2.5 3.0 4.0 5.0]

    #define VOLUMETRIC_CLOUDS
    #define CLOUD_RAY_STEPS 24 // [16 24 32 40 48]
    #define CLOUD_REFLECTION_STEPS 12 // [6 8 12 16 24 32]
    #define CLOUD_COVERAGE 1.3 // [0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5]
    #define CLOUD_DENSITY 0.4 // [0.2 0.3 0.4 0.5 0.6 0.8 1.0]
    #define CLOUD_ALTITUDE 1200.0 // [400.0 600.0 800.0 1000.0 1200.0 1500.0 2000.0 2500.0 3000.0]
    #define CLOUD_THICKNESS 1200.0 // [300.0 400.0 500.0 700.0 900.0 1200.0]
    #define CLOUD_SCALE 2.0 // [0.5 0.75 1.0 1.5 2.0 3.0]
    #define CLOUD_SUNLIGHTING 1.15 // [0.5 0.75 1.0 1.15 1.25 1.5 2.0]
    #define CLOUD_SKYLIGHTING 1.15 // [0.5 0.75 1.0 1.15 1.25 1.5 2.0]
    #define CLOUD_UPSCALING 0 // [0 2 4]

    #define VOLUMETRIC_LIGHT
    #define VL_STEPS 12 // [8 12 16 24 32]
    #define VL_DENSITY 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0 4.0]

    #define PLAYER_CULL
    #define MAX_QUADS 262144 // [65536 131072 262144 524288]

#endif
