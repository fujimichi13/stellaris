

layout(local_size_x=256) in;
const ivec3 workGroups=ivec3(1,1,1);

layout(r32ui) coherent uniform uimage2D histXY;
layout(r32f)  coherent uniform image2D warpXY;

shared float sX[256];
shared float sY[256];
shared float scanX[2][256];
shared float scanY[2][256];

float loadHist(int i,int row){
    return (i<0||i>=256)?0.:float(imageLoad(histXY,ivec2(i,row)).r);
}

void shBarrier(){
    memoryBarrierShared();
    barrier();
}

void main(){
    int bin=int(gl_LocalInvocationID.x);

    sX[bin]=loadHist(bin,0);
    sY[bin]=loadHist(bin,1);
    shBarrier();

    float bx=3.*sX[bin];
    float by=3.*sY[bin];
    bx+=2.*sX[max(bin-1,0)]*float(bin>=1)+sX[max(bin-2,0)]*float(bin>=2);
    by+=2.*sY[max(bin-1,0)]*float(bin>=1)+sY[max(bin-2,0)]*float(bin>=2);
    bx+=2.*sX[min(bin+1,255)]*float(bin<=254)+sX[min(bin+2,255)]*float(bin<=253);
    by+=2.*sY[min(bin+1,255)]*float(bin<=254)+sY[min(bin+2,255)]*float(bin<=253);

    scanX[0][bin]=bx;
    scanY[0][bin]=by;
    shBarrier();

    int src=0;
    for(int offset=1;offset<256;offset<<=1){
        int dst=1-src;
        scanX[dst][bin]=scanX[src][bin]+((bin>=offset)?scanX[src][bin-offset]:0.);
        scanY[dst][bin]=scanY[src][bin]+((bin>=offset)?scanY[src][bin-offset]:0.);
        shBarrier();
        src=dst;
    }

    float totalX=scanX[src][255];
    float totalY=scanY[src][255];

    float uniformCdf=float(bin+1)/256.;
    float measuredX=(totalX>0.)?scanX[src][bin]/totalX:uniformCdf;
    float measuredY=(totalY>0.)?scanY[src][bin]/totalY:uniformCdf;
    float targetX=mix(measuredX,uniformCdf,.3);
    float targetY=mix(measuredY,uniformCdf,.3);

    float oldX=imageLoad(warpXY,ivec2(bin,0)).r;
    float oldY=imageLoad(warpXY,ivec2(bin,1)).r;
    if(oldX<=0.) oldX=uniformCdf;
    if(oldY<=0.) oldY=uniformCdf;

    imageStore(warpXY,ivec2(bin,0),vec4(mix(oldX,targetX,.05)));
    imageStore(warpXY,ivec2(bin,1),vec4(mix(oldY,targetY,.05)));
}