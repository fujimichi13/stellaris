#version 430 compatibility

#include "/lib/atmosphere/constants.glsl"
#include "/lib/atmosphere/geometry.glsl"
#include "/lib/atmosphere/transmittance.glsl"
#include "/lib/atmosphere/scattering.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform sampler2D noisetex;
uniform sampler2D samplerTransmittance;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;
uniform vec3 cameraPosition;

in vec2 texcoord;

/* RENDERTARGETS:0 */
layout(location = 0) out vec4 color;

vec3 worldSpacePosition(vec2 uv, float depth) {
    vec4 clip=vec4(uv*2.-1.,depth*2.-1.,1.);
    vec4 viewSpace=gbufferProjectionInverse*clip;
    viewSpace/=viewSpace.w;
    vec4 worldSpace=gbufferModelViewInverse*viewSpace;
    return worldSpace.xyz;
}

float bluenoise(vec2 p){
    return texelFetch(noisetex,ivec2(p)&127,0).r;
}

vec3 ACES(vec3 v){
    v*=.6;
    return clamp((v*(2.51*v+.03))/(v*(2.43*v+.59)+.14),0.,1.);
}

void main(){
    vec4 albedo=texture(colortex0,texcoord);
    float depth=texture(depthtex0,texcoord).r;

    vec3 p=worldSpacePosition(texcoord,depth);
    float dist=length(p)*.001;
    vec3 V=normalize(p);
    vec3 S=normalize(mat3(gbufferModelViewInverse)*sunPosition);
    vec3 X=vec3(0.,max(cameraPosition.y,1.)*.001,0.);

    float mu;
    float mu_s;
    float r;
    bool ground;
    float d;
    float nu;
    bool hit=getIntersectionInfo(X,V,S,mu,mu_s,r,ground,d,nu);

    color=albedo;
    if(!hit) return;

    vec2 lutRes=vec2(256.,64.);
    if(depth<1.) d=min(d,dist);

    vec3 rayleigh;
    vec3 mie;
    calcSingleScattering(r,mu,mu_s,d,nu,ground,samplerTransmittance,lutRes,bluenoise(gl_FragCoord.xy),rayleigh,mie);
    vec3 scatter=(rayleigh*RayleighPhaseFunction(nu)+mie*MiePhaseFunction(.7,nu))*50.;

    if(depth<1.){
        vec3 T=getTransmittance(mu,r,d,ground,samplerTransmittance,lutRes);
        color=vec4(albedo.rgb*T+ACES(scatter),albedo.a);
    }else{
        vec3 sun=ground?vec3(0.):getTransmittanceToAtmTop(mu,r,samplerTransmittance,lutRes)*smoothstep(.9998,.99985,nu)*100.;
        color=vec4(ACES(scatter+sun),1.);
    }
}