#version 430 compatibility

#include "/lib/atmosphere/constants.glsl"
#include "/lib/atmosphere/geometry.glsl"
#include "/lib/atmosphere/transmittance.glsl"
#include "/lib/atmosphere/scattering.glsl"

layout(local_size_x=8,local_size_y=8) in;

const ivec3 workGroups=ivec3(32,8,1);

layout(rgba32f) uniform image2D transmittanceLut;

void main(){
    ivec2 px=ivec2(gl_GlobalInvocationID.xy);
    vec2 uv=(vec2(px)+.5)/vec2(256.,64.);

    float mu;
    float r;
    uv2muR(uv,mu,r,vec2(256.,64.));

    imageStore(transmittanceLut,px,vec4(calcTransmittanceToAtmTop(mu,r),1.));
}