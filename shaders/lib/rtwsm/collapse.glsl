#ifndef RTWSM_COLLAPSE_GLSL
    #define RTWSM_COLLAPSE_GLSL a

    #include "/lib/rtwsm/getWarp.glsl"

    layout(r32ui) uniform uimage2D rtwImportance;

    shared float rtwCollapsed[2][512];
    shared float rtwReduce[2][512];

    void rtwsmCollapse(int t){
        float iu=0.;
        float iv=0.;
        for(int k=0;k<512;k++){
            iu=max(iu,uintBitsToFloat(imageLoad(rtwImportance,ivec2(t,k)).r));
            iv=max(iv,uintBitsToFloat(imageLoad(rtwImportance,ivec2(k,t)).r));
        }
        rtwCollapsed[0][t]=iu;
        rtwCollapsed[1][t]=iv;
        rtwReduce[0][t]=iu;
        rtwReduce[1][t]=iv;
        memoryBarrierShared();
        barrier();

        for(int s=512>>1;s>0;s>>=1){
            if(t<s){
                rtwReduce[0][t]=max(rtwReduce[0][t],rtwReduce[0][t+s]);
                rtwReduce[1][t]=max(rtwReduce[1][t],rtwReduce[1][t+s]);
            }
            memoryBarrierShared();
            barrier();
        }

        float peakU=rtwReduce[0][0];
        float peakV=rtwReduce[1][0];
        memoryBarrierShared();
        barrier();

        rtwCollapsed[0][t]=(peakU>0.)?iu/peakU:1.;
        rtwCollapsed[1][t]=(peakV>0.)?iv/peakV:1.;
        memoryBarrierShared();
        barrier();
    }

#endif