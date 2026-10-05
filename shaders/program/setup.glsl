

#include "/lib/atmosphere/transmittance.glsl"

layout(local_size_x=16,local_size_y=16) in;
const ivec3 workGroups=ivec3(16,4,1);

layout(rgba32f) uniform image2D transmittanceLut;

void main(){
    ivec2 id=ivec2(gl_GlobalInvocationID.xy);
    vec2 uv=(vec2(id)+.5)/vec2(256.,64.);
    imageStore(transmittanceLut,id,calcTransmittance(uv.x*2.-1.,mix(R,RA,uv.y)));
}