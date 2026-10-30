#ifndef SETTINGS_GLSL
    #define SETTINGS_GLSL a

    /*
    const int colortex0Format=RGBA16F;
    const int colortex3Format=RGBA32UI;
    const int colortex5Format=RGBA16F;
    const int colortex7Format=RGBA16F;
    const int colortex8Format=RGBA16F;
    const int colortex12Format=RGBA16F;
    const int colortex13Format=RGBA16F;
    const int colortex15Format=RGBA16F;

    const bool shadowtex0Nearest=true;
    const bool shadowtex1Nearest=true;

    const bool colortex5Clear=false;
    const bool colortex15Clear=false;
    
    const float shadowDistanceRenderMul = 1.0;
    */

    #define MAT_TERRAIN 0u
    #define MAT_ENTITY 10u
    #define MAT_HAND 20u
    
    #ifdef BLOOM
    #endif
    #ifdef TAA_ENABLED
    #endif

    #define COLORED_SHADOW

    #define PT_BOUNCES 2 // [1 2 3 4]
    #define PT_SAMPLES 1 // [1 2 3 4]

    #define MAX_QUADS 262144 // [65536 131072 262144 524288]

    #define BLOOM
    #define BLOOM_STRENGTH 0.1 // [0.0 0.02 0.05 0.1 0.15 0.2 0.3 0.5]

    #define WAVE_SCALE 0.004 // [0.0005 0.001 0.002 0.003 0.004 0.005 0.006 0.008 0.010 0.015 0.020]
    #define WAVE_SPEED 0.0067 // [0.0 0.002 0.004 0.0067 0.010 0.015 0.020 0.030 0.050]
    #define WAVE_HEIGHT 1.5 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0 2.5 3.0 4.0]
    #define WAVE_PARALLAX_STRENGTH 0.7 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.25 1.5]
    #define WAVE_OCTAVES 6 // [2 3 4 5 6 7 8]

    #define WATER_FOG_DENSITY 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0 4.0]
    #define WATER_FOG_SCATTERING 0.03 // [0.0 0.01 0.02 0.03 0.04 0.05 0.075 0.10 0.15 0.20]

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
    #define EXPOSURE_MAX 3.5 // [0.0 0.5 1.0 1.5 2.0 2.5 3.0 3.5 4.0 5.0]
    #define NIGHT_BRIGHTNESS 0.5 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0 2.5 3.0 4.0]

    #define VOLUMETRIC_CLOUDS
    #define CLOUD_RAY_STEPS 80 // [16 24 32 40 48 64 72 80 88 92]
    #define CLOUD_COVERAGE 1.0 // [0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5]
    #define CLOUD_DENSITY 0.8 // [0.2 0.3 0.4 0.5 0.6 0.8 1.0]
    #define CLOUD_ALTITUDE 1400.0 // [400.0 450.0 500.0 550.0 600.0 650.0 700.0 750.0 800.0 850.0 900.0 950.0 1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 2100.0 2200.0 2300.0 2400.0 2500.0 2600.0 2700.0 2800.0 2900.0 3000.0]
    #define CLOUD_THICKNESS 1200.0 // [400.0 450.0 500.0 550.0 600.0 650.0 700.0 750.0 800.0 850.0 900.0 950.0 1000.0 1100.0 1200.0 1300.0 1400.0 1500.0 1600.0 1700.0 1800.0 1900.0 2000.0 2100.0 2200.0 2300.0 2400.0 2500.0 2600.0 2700.0 2800.0 2900.0 3000.0]
    #define CLOUD_SCALE 2.0 // [0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0 1.05 1.1 1.15 1.2 1.25 1.3 1.35 1.4 1.45 1.5 1.55 1.6 1.65 1.7 1.75 1.8 1.85 1.9 1.95 2.0 2.05 2.1 2.15 2.2 2.25 2.3 2.35 2.4 2.45 2.5 2.55 2.6 2.65 2.7 2.75 2.8 2.85 2.9 2.95 3.0]
    #define CLOUD_SUNLIGHTING 1.0 // [0.5 0.75 1.0 1.15 1.25 1.5 2.0]
    #define CLOUD_SKYLIGHTING 1.15 // [0.5 0.75 1.0 1.15 1.25 1.5 2.0]
    #define CLOUD_UPSCALING 0 // [0 2 4]
    #define CLOUD_WIND_SPEED 4.0 // [0.0 2.0 4.0 7.0 10.0 15.0 20.0 30.0]

    #define VOLUMETRIC_LIGHT
    #define VL_STEPS 12 // [8 12 16 24 32]
    #define VL_DENSITY 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0 4.0]

    #define VOXELIZE_PLAYER

    #define INFO ST // [ST LS]
    #define VERSION ST // [ST LS]
    
#endif