#ifndef UNIFORMS_GLSL
    #define UNIFORMS_GLSL a

    uniform sampler2D noisetex;

    uniform sampler2D colortex0;
    uniform sampler2D colortex1;
    uniform sampler2D colortex2;
    uniform sampler2D colortex3;
    uniform sampler2D colortex4;
    uniform sampler2D colortex5;
    uniform sampler2D colortex6;
    uniform sampler2D colortex7;
    uniform sampler2D colortex8;
    uniform sampler2D colortex9;
    uniform sampler2D colortex10;
    uniform sampler2D colortex11;
    uniform sampler2D colortex12;
    uniform sampler2D colortex13;
    uniform sampler2D colortex14;
    uniform sampler2D colortex15;

    uniform sampler2D depthtex0;
    uniform sampler2D depthtex1;
    uniform sampler2D depthtex2;

    uniform sampler2D shadowtex0;
    uniform sampler2D shadowtex1;

    uniform sampler2D shadowcolor0;
    uniform sampler2D shadowcolor1;
    
    uniform sampler2D tex;
    uniform sampler2D normals;
    uniform sampler2D specular;

    uniform sampler2D samplerTransmittance;
    uniform sampler2D samplerSky;
    
    uniform sampler2D samplerWarpX;
    uniform sampler2D samplerWarpY;

    uniform float viewWidth;
    uniform float viewHeight;

    uniform int frameCounter;

    uniform mat4 gbufferProjection;
    uniform mat4 gbufferProjectionInverse;
    uniform mat4 gbufferPreviousProjection;
    uniform mat4 gbufferModelView;
    uniform mat4 gbufferModelViewInverse;
    uniform mat4 gbufferPreviousModelView;
    uniform mat4 shadowProjection;
    uniform mat4 shadowProjectionInverse;
    uniform mat4 shadowModelView;
    uniform mat4 shadowModelViewInverse;

    uniform vec3 shadowLightPosition;
    uniform vec3 sunPosition;

    uniform vec3 cameraPosition;
    uniform vec3 previousCameraPosition;

#endif