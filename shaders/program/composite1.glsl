

#ifdef vsh

    out vec2 texcoord;

    void main(){
        gl_Position=ftransform();
        texcoord=(gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;
    }

#endif

#ifdef fsh

    #include "/settings.glsl"
    #include "/lib/utility/uniforms.glsl"

    /*
    const int colortex5Format = RGBA16F;
    const int colortex6Format = R32F;

    const bool colortex5Clear = false;
    const bool colortex6Clear = false;
    */

    in vec2 texcoord;

    /* RENDERTARGETS:5,6 */
    layout(location = 0) out vec4 color;
    layout(location = 1) out vec4 color1;

    float rtwsmWarp1D(sampler2D tex, float u, out float slope){
        slope=1.;
        if(u<=0.||u>=1.) return u;

        float t=u*float(256);
        int i=min(int(t),256-1);
        float f=t-float(i);

        float hi=texelFetch(tex,ivec2(i,0),0).r;
        if(hi<=0.) return u;

        float lo=(i==0)?0.:texelFetch(tex,ivec2(i-1,0),0).r;

        slope=max((hi-lo)*float(256),1e-3);
        return mix(lo,hi,f);
    }

    vec2 rtwsmWarp(vec2 clipXY, out vec2 slope){
        vec2 uv=clipXY*.5+.5;
        vec2 w;
        w.x=rtwsmWarp1D(samplerWarpX,uv.x,slope.x);
        w.y=rtwsmWarp1D(samplerWarpY,uv.y,slope.y);
        return w*2.-1.;
    }

    vec4 toShadowClip(vec3 worldPos){
        vec4 c=shadowProjection*(shadowModelView*vec4(worldPos,1.));
        return vec4(c.xyz/c.w,1.);
    }

    vec2 bluenoise(vec2 fragCoord){
        return texelFetch(noisetex,ivec2(fragCoord)&127,0).rg;
    }

    vec3 worldSpacePosition(vec2 uv, float depth){
        vec4 v=gbufferProjectionInverse*vec4(uv*2.-1.,depth*2.-1.,1.);
        return (gbufferModelViewInverse*vec4(v.xyz/v.w,1.)).xyz;
    }

    #include "/lib/lighting/globalIllumination.glsl"

    void main(){
        color=vec4(0.);
        color1=vec4(0.);

        ivec2 hp=ivec2(gl_FragCoord.xy);
        ivec2 fullRes=ivec2(viewWidth,viewHeight);

        ivec2 jit=ivec2(frameCounter&1,(frameCounter>>1)&1);
        ivec2 fp=min(hp*2+jit,fullRes-1);

        float depth=texelFetch(depthtex0,fp,0).r;
        if(texelFetch(colortex13,fp,0).w>.5) depth=texelFetch(depthtex1,fp,0).r;
        if(depth>=1.) return;

        vec4 nd=texelFetch(colortex3,fp,0);
        if(dot(nd.xyz,nd.xyz)<.25) return;

        float skyLm=texelFetch(colortex4,fp,0).g;
        //if(skyLm<.15) return;
        if(skyLm<.5) return;

        vec3 N=normalize(nd.xyz);
        vec3 worldPos=worldSpacePosition((vec2(fp)+.5)/vec2(fullRes),depth);

        color=rsmTemporal(worldPos,RSM(worldPos,N));
        color1=vec4(length(worldPos),0.,0.,0.);
    }

#endif