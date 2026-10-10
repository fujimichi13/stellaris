

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
    const int colortex1Format = RGBA32F;
    const bool colortex1Clear = false;
    */

    in vec2 texcoord;

    /* RENDERTARGETS:1 */
    layout(location = 0) out vec4 color;

    void main(){
        if(any(notEqual(ivec2(gl_FragCoord.xy),ivec2(0)))) discard;

        vec4 prev=texelFetch(colortex1,ivec2(0),0);
        float dt=max(frameTimeCounter-prev.g,0.);

        const int N=24;
        ivec2 res=ivec2(viewWidth,viewHeight);

        float sum=0.;
        for(int y=0;y<N;y++){
            for(int x=0;x<N;x++){
                vec2 uv=(vec2(x,y)+.5)/float(N);
                vec3 c=texelFetch(colortex0,ivec2(uv*vec2(res)),0).rgb;
                sum+=log2(dot(c,vec3(.2126,.7152,.0722))+1e-4);
            }
        }

        float avg=exp2(sum/float(N*N));

        float targetEV=log2(.9/(avg*.0625*2.3));
        targetEV=clamp(targetEV,EXPOSURE_MIN,EXPOSURE_MAX);

        float k=1.-exp(-dt*1.5);

        color=vec4(mix(prev.r,targetEV,k),frameTimeCounter,0.,1.);
    }

#endif