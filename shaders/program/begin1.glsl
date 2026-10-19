

#include "/settings.glsl"
#include "/lib/voxel/voxel.glsl"

layout(local_size_x=256) in;
const ivec3 workGroups=ivec3(1024,1,1);

void main(){
    uint id=gl_GlobalInvocationID.x;
    const uint stride=uint(1024)*256u;

    if(id==0u){
        vxh.quadCount=0u;
        vxh.overflow=0u;
        vxh.vMX=encode(3.0e38);
        vxh.vMY=encode(3.0e38);
        vxh.vMZ=encode(3.0e38);
        vxh.vMxX=encode(-3.0e38);
        vxh.vMxY=encode(-3.0e38);
        vxh.vMxZ=encode(-3.0e38);
        vxl.lightCount=0u;
    }
    for(uint i=id; i<uint(16384); i += stride) vxl.cellCount[i]=0u;
    for(uint i=id; i<uint(262144); i += stride) vxh.bucketCount[i]=0u;
    for(uint i=id; i<uint(MAX_QUADS); i += stride) vxa.flags[i]=0u;
}