#ifndef RTWSM_BACKWARDANALYSIS_GLSL
    #define RTWSM_BACKWARDANALYSIS_GLSL a

    #include "/lib/rtwsm/getWarp.glsl"

    layout(r32ui) uniform uimage2D rtwImportance;

    float rtwImportanceDesiredView(vec3 shadowNdc){
        bool inside=all(greaterThanEqual(shadowNdc,vec3(-1.)))&&all(lessThanEqual(shadowNdc,vec3(1.)));
        return inside?1.:0.;
    }

    float rtwImportanceDistance(float depth01){
        return clamp(1.-(depth01*2.-1.),0.,2.);
    }

    float rtwImportanceNormal(vec3 n,vec3 vd){
        return 1.+2.*clamp(-dot(n,vd),0.,1.);
    }

    float rtwImportancee(vec3 shadowNdc,float depth01,vec3 n,vec3 vd){
        return rtwImportanceDesiredView(shadowNdc)
            * rtwImportanceDistance(depth01)
            * rtwImportanceNormal(n,vd);
    }

    void rtwsmBackwardAnalysis(ivec2 px,vec3 worldPos,float depth01,vec3 n){
        if(((px.x|px.y)&1)!=0) return;

        vec4 sc=shadowProjection*(shadowModelView*vec4(worldPos,1.));
        vec3 ndc=sc.xyz/sc.w;

        float I=rtwImportancee(ndc,depth01,n,normalize(worldPos));
        if(I<=0.) return;

        ivec2 cell=clamp(ivec2((ndc.xy*.5+.5)*float(512)),ivec2(0),ivec2(512-1));
        imageAtomicMax(rtwImportance,cell,floatBitsToUint(I));
    }

#endif