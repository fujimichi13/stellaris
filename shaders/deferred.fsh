#version 430 compatibility

#include "/lib/atmosphere/scattering.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform sampler2D samplerTransmittance;
uniform sampler2D samplerSky;

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

//https://github.com/TheRealMJP/BakingLab/blob/master/BakingLab/ACES.hlsl
vec3 ACES(vec3 v){
    v=mat3(.59719,.0760,.0284,.35458,.90834,.13383,.04823,.01566,.83777)*max(v,0.)*.0625;
    v=(v*(v+.0245786)-.000090537)/(v*(.983729*v+.432951)+.238081);
    return clamp(mat3(1.60475,-.10208,-.00327,-.53108,1.10813,-.07276,-.07367,-.00605,1.07602)*v,0.,1.);
}

void main(){
    vec4 albedo=texture(colortex0,texcoord);
    float depth=texture(depthtex0,texcoord).r;

    color=albedo;
    if(depth<1.) return;

    vec3 V=normalize(worldSpacePosition(texcoord,depth));
    vec3 S=normalize(mat3(gbufferModelViewInverse)*sunPosition);
    float alt=eyeAlt(cameraPosition.y);
    float disc=smoothstep(.9998,.99985,dot(V,S));

    vec3 sky;
    vec3 sun;
    if(alt>50.){
        vec3 O=vec3(0.,R+alt,0.);
        vec4 T;
        float g;
        vec4 L=calcInscattering(O,V,S,samplerTransmittance,T,g);
        if(g>0.){
            vec3 N=normalize(O+V*g);
            float c=dot(N,S);
            L+=T*sunIrr*vec4(.04,.06,.1,.11)*lutT(samplerTransmittance,c,0.)*max(c,0.);
        }
        sky=toRGB(L);
        sun=toRGB(sunIrr*T)*disc*(g<0.?1.:0.)*30.;
    }else{
        float t=max(asin(clamp(V.y,-1.,1.)),0.);
        sky=texture(samplerSky,vec2(atan(V.z,V.x)*.15915494+.5,sqrt(t*.63661977)*.5+.5)).rgb;
        sky*=1.-.6*smoothstep(0.,-.4,V.y);
        sun=toRGB(sunIrr*lutT(samplerTransmittance,S.y,alt*.01))*disc*smoothstep(-.02,0.,V.y)*30.;
    }

    color=vec4(pow(ACES(sky+sun),vec3(.4545455)),1.);
}