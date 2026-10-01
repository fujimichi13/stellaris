#version 430 compatibility

#include "/lib/atmosphere/scattering.glsl"

layout(local_size_x=16,local_size_y=16) in;

const ivec3 workGroups=ivec3(16,8,1);

layout(rgba32f) uniform image2D skyLut;

uniform sampler2D samplerTransmittance;

uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;
uniform vec3 cameraPosition;

void main(){
    float alt=eyeAlt(cameraPosition.y);
    if(alt>50.) return;

    ivec2 id=ivec2(gl_GlobalInvocationID.xy);
    vec2 uv=(vec2(id)+.5)/vec2(256.,128.);

    float az=(uv.x-.5)*6.2831853;
    float l=uv.y*2.-1.;
    float el=l*l*sign(l)*1.5707963;
    vec3 V=vec3(cos(el)*cos(az),sin(el),cos(el)*sin(az));
    vec3 S=normalize(mat3(gbufferModelViewInverse)*sunPosition);
    vec3 O=vec3(0.,R+alt,0.);
    vec4 T;
    float g;

    imageStore(skyLut,id,vec4(toRGB(calcInscattering(O,V,S,samplerTransmittance,T,g)),1.));
}