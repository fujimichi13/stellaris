#ifndef SETTINGS_GLSL
    #define SETTINGS_GLSL a

    #define COLORED_SHADOW
    #define RSM_ENABLED

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

    #define SKYLIGHT_CURVE 6.0 // [3.0 4.0 5.0 6.0 8.0 10.0 12.0]

    #define TAA_ENABLED
    #define TAA_BLENDWEIGHT 0.90 // [0.50 0.60 0.70 0.75 0.80 0.85 0.88 0.90 0.92 0.94 0.96 0.98]
    #define TAA_AGGRESSION 0.50  // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]

    #define EXPOSURE_MIN -2.0 // [-5.0 -4.0 -3.0 -2.5 -2.0 -1.5 -1.0 -0.5 0.0]
    #define EXPOSURE_MAX 2.0 // [0.0 0.5 1.0 1.5 2.0 2.5 3.0 4.0 5.0]

#endif