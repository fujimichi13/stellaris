#ifndef RTWSM_GETWARP_GLSL
    #define RTWSM_GETWARP_GLSL a

    float rtwsmWarp1D(sampler2D lut,float u,int row,out float slope){
        slope=1.;
        if(u<=0.||u>=1.) return u;

        float t=u*float(512);
        int i=min(int(t),512-1);

        float hi=texelFetch(lut,ivec2(i,row),0).r;
        if(hi<=0.) return u;

        float lo=(i==0)?0.:texelFetch(lut,ivec2(i-1,row),0).r;
        slope=max((hi-lo)*float(512),1e-3);
        return mix(lo,hi,t-float(i));
    }

    vec2 rtwsmWarpUV(sampler2D lut,vec2 uv,out vec2 slope){
        return vec2(rtwsmWarp1D(lut,uv.x,0,slope.x),rtwsmWarp1D(lut,uv.y,1,slope.y));
    }

    vec2 rtwsmWarpUV(sampler2D lut,vec2 uv){
        vec2 slope;
        return rtwsmWarpUV(lut,uv,slope);
    }

    vec2 rtwsmWarpClip(sampler2D lut,vec2 clipXY,out vec2 slope){
        return rtwsmWarpUV(lut,clipXY*.5+.5,slope)*2.-1.;
    }

    vec2 rtwsmWarpClip(sampler2D lut,vec2 clipXY){
        vec2 slope;
        return rtwsmWarpClip(lut,clipXY,slope);
    }

#endif