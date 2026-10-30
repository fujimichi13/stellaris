#ifndef RTWSM_BUILDWARP_GLSL
    #define RTWSM_BUILDWARP_GLSL a

    #include "/lib/rtwsm/getWarp.glsl"
    #include "/lib/rtwsm/collapse.glsl"

    layout(r32f) uniform image2D warpXY;

    shared float rtwScan[2][2][512];

    void rtwsmBuildWarp(int t,float impU,float impV){
        rtwScan[0][0][t]=max(impU,.001);
        rtwScan[1][0][t]=max(impV,.001);
        memoryBarrierShared();
        barrier();

        int src=0;
        for(int offset=1;offset<512;offset<<=1){
            int dst=1-src;
            rtwScan[0][dst][t]=rtwScan[0][src][t]+((t>=offset)?rtwScan[0][src][t-offset]:0.);
            rtwScan[1][dst][t]=rtwScan[1][src][t]+((t>=offset)?rtwScan[1][src][t-offset]:0.);
            memoryBarrierShared();
            barrier();
            src=dst;
        }

        float warpU=rtwScan[0][src][t]/rtwScan[0][src][512-1];
        float warpV=rtwScan[1][src][t]/rtwScan[1][src][512-1];

        float oldU=imageLoad(warpXY,ivec2(t,0)).r;
        float oldV=imageLoad(warpXY,ivec2(t,1)).r;
        if(oldU>0.) warpU=mix(oldU,warpU,.5);
        if(oldV>0.) warpV=mix(oldV,warpV,.5);

        if(t==512-1){
            warpU=1.;
            warpV=1.;
        }

        imageStore(warpXY,ivec2(t,0),vec4(warpU));
        imageStore(warpXY,ivec2(t,1),vec4(warpV));
    }

#endif