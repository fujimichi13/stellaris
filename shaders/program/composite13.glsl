

#include "/lib/rtwsm/getWarp.glsl"

layout(local_size_x=512) in;
const ivec3 workGroups=ivec3(1,1,1);

#include "/lib/rtwsm/collapse.glsl"
#include "/lib/rtwsm/blurimportance.glsl"
#include "/lib/rtwsm/buildWarp.glsl"

void main(){
    int t=int(gl_LocalInvocationID.x);

    rtwsmCollapse(t);

    float impU;
    float impV;
    rtwsmBlurImportance(t,impU,impV);

    rtwsmBuildWarp(t,impU,impV);
}