

layout(local_size_x=256) in;
const ivec3 workGroups=ivec3(1,1,1);

layout(r32ui) uniform uimage2D histX;
layout(r32ui) uniform uimage2D histY;
layout(r32f) uniform image2D warpX;
layout(r32f) uniform image2D warpY;

shared float sX[256];
shared float sY[256];
shared float scanX[256];
shared float scanY[256];

float loadX(int i){
    return (i<0||i>=256)?0.:float(imageLoad(histX,ivec2(i,0)).r);
}
float loadY(int i){
    return (i<0||i>=256)?0.:float(imageLoad(histY,ivec2(i,0)).r);
}

void main(){
    int bin=int(gl_LocalInvocationID.x);

    sX[bin]=loadX(bin);
    sY[bin]=loadY(bin);
    barrier();

    float bx=sX[max(bin-2,0)]*float(bin>=2)
            +2.*sX[max(bin-1,0)]*float(bin>=1)
            +3.*sX[bin]
            +2.*sX[min(bin+1,255)]*float(bin<=254)
            +sX[min(bin+2,255)]*float(bin<=253);

    float by=sY[max(bin-2,0)]*float(bin>=2)
            +2.*sY[max(bin-1,0)]*float(bin>=1)
            +3.*sY[bin]
            +2.*sY[min(bin+1,255)]*float(bin<=254)
            +sY[min(bin+2,255)]*float(bin<=253);
    barrier();

    scanX[bin]=bx;
    scanY[bin]=by;
    barrier();

    for(int offset=1;offset<256;offset<<=1){
        float ax=(bin>=offset)?scanX[bin-offset]:0.;
        float ay=(bin>=offset)?scanY[bin-offset]:0.;
        barrier();
        scanX[bin]+=ax;
        scanY[bin]+=ay;
        barrier();
    }

    float totalX=scanX[255];
    float totalY=scanY[255];

    float uniformCdf=float(bin+1)/256.;
    float measuredX=(totalX>0.)?scanX[bin]/totalX:uniformCdf;
    float measuredY=(totalY>0.)?scanY[bin]/totalY:uniformCdf;
    float targetX=mix(measuredX,uniformCdf,.3);
    float targetY=mix(measuredY,uniformCdf,.3);

    float oldX=imageLoad(warpX,ivec2(bin,0)).r;
    float oldY=imageLoad(warpY,ivec2(bin,0)).r;
    if(oldX<=0.) oldX=uniformCdf;
    if(oldY<=0.) oldY=uniformCdf;

    imageStore(warpX,ivec2(bin,0),vec4(mix(oldX,targetX,.05)));
    imageStore(warpY,ivec2(bin,0),vec4(mix(oldY,targetY,.05)));
}