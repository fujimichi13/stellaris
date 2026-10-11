

#include "/settings.glsl"

layout(local_size_x=16,local_size_y=16) in;
const ivec3 workGroups=ivec3(32,32,1);

layout(rgba16f) uniform image2D causticLut;

uniform sampler2D noisetex;
uniform float frameTimeCounter;
uniform vec3 cameraPosition;
uniform vec3 shadowLightPosition;
uniform mat4 gbufferModelViewInverse;

#define texture(s,uv) textureLod(s,uv,0.)
#include "/lib/water/water.glsl"
#undef texture

shared float Hs[20][20];
shared vec2 Ts[18][18];

void main(){
    vec3 L=normalize(mat3(gbufferModelViewInverse)*shadowLightPosition);
    if(L.y<.05) return;

    float ts=CAUSTICS_MAP_BLOCKS/float(CAUSTICS_MAP_RES);
    vec2 origin=floor(cameraPosition.xz/ts)*ts-.5*CAUSTICS_MAP_BLOCKS;

    ivec2 base=ivec2(gl_WorkGroupID.xy)*16;
    int tid=int(gl_LocalInvocationIndex);

    for(int i=tid;i<400;i+=256){
        ivec2 o=ivec2(i%20,i/20)-2;
        Hs[i/20][i%20]=wH(origin+(vec2(base+o)+.5)*ts,true);
    }
    memoryBarrierShared();
    barrier();

    for(int i=tid;i<324;i+=256){
        ivec2 n=ivec2(i%18,i/18);
        vec2 g=vec2(Hs[n.y+1][n.x+2]-Hs[n.y+1][n.x],Hs[n.y+2][n.x+1]-Hs[n.y][n.x+1])/(2.*ts);
        vec3 N=normalize(vec3(-g.x*2.,1.,-g.y*2.));
        vec3 R=refract(-L,N,1./1.333);
        Ts[n.y][n.x]=R.xz/max(-R.y,.05);
    }
    memoryBarrierShared();
    barrier();

    ivec2 lid=ivec2(gl_LocalInvocationID.xy);
    vec2 dTdx=(Ts[lid.y+1][lid.x+2]-Ts[lid.y+1][lid.x])/(2.*ts);
    vec2 dTdz=(Ts[lid.y+2][lid.x+1]-Ts[lid.y][lid.x+1])/(2.*ts);
    imageStore(causticLut,base+lid,vec4(dTdx.x,dTdz.x,dTdx.y,dTdz.y));
}
