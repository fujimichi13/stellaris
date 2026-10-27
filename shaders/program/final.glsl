

#ifdef vsh

    out vec2 texcoord;

    void main(){
        gl_Position=ftransform();
        texcoord=(gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;
    }

#endif

#ifdef fsh

    #include "/settings.glsl"
    #include "/lib/utility/math.glsl"
    #include "/lib/utility/uniforms.glsl"
    #include "/lib/camera/bloom.glsl"

    in vec2 texcoord;

    layout(location=0) out vec4 color;

    vec3 AgxDefaultContrastApprox(vec3 x){
        return (((((15.5*x-40.14)*x+31.96)*x-6.868)*x+.4298)*x+.1191)*x-.00232;
    }

    vec3 AgX(vec3 color){
        color=max(color,0.)*.0625;
        color*=2.3;

        color*=mat3(0.99999976,-1.26657e-7,-1.29064e-9,1.67316e-8,0.99999976,-5.32026e-9,-0.00725587,6.47740e-9,1.00725580);
        color*=mat3(0.842479062253094,0.0784335999999992,0.0792237451477643,0.0423282422610123,0.878468636469772,0.0791661274605434,0.0423756549057051,0.0784336,0.879142973793104);

        const float hev=14.*.5;
        const float middle_grey=.18;
        color=clamp(log2(max(color,1e-6)/middle_grey),-hev,hev);
        color=(color+hev)/14.;

        color=AgxDefaultContrastApprox(color);

        color*=mat3(1.19687900512017,-0.0980208811401368,-0.0990297440797205,-0.0528968517574562,1.15190312990417,-0.0989611768448433,-0.0529716355144438,-0.0980434501171241,1.15107367264116);

        return clamp(color,0.,1.);
    }

    void main(){
        vec4 c=texture(colortex0,texcoord);

        #ifdef BLOOM
            vec3 bloom=upsampleTent9(samplerBloom1,texcoord,1./vec2(textureSize(samplerBloom1,0)),1.);
        #else
            vec3 bloom=vec3(0.);
        #endif
        vec3 hdr=c.rgb+bloom*(BLOOM_STRENGTH/.0625);

        float rainAmt=rainStrength*smoothstep(60.,200.,float(eyeBrightnessSmooth.y));
        if(rainAmt>.01&&isEyeInWater==0){
            vec2 ruv=rUV(texcoord);
            float dp=texture(depthtex0,ruv).r;
            vec4 sv=gbufferProjectionInverse*vec4(texcoord*2.-1.,dp*2.-1.,1.);
            float sceneDist=(dp<1.)?length(sv.xyz/sv.w):1e5;
            vec4 rv=gbufferProjectionInverse*vec4(texcoord*2.-1.,1.,1.);
            vec3 dir=normalize(mat3(gbufferModelViewInverse)*normalize(rv.xyz/rv.w));
            float hl=max(length(dir.xz),1e-3);

            const float RADII[8]=float[8](2.5,4.,6.,9.,13.,19.,27.,38.);
            float streak=0.;
            for(int i=0;i<8;i++){
                float r=RADII[i];
                float t=r/hl;
                if(t>=sceneDist) continue;
                vec3 p=dir*t;
                float pixW=t*abs(gbufferProjectionInverse[1][1])*2./viewHeight;

                const float CW=.2;
                float u=atan(p.z,p.x)*r+p.y*.18;
                float cu=floor(u/CW);
                float fu=fract(u/CW)-.5;
                float h=hash21(vec2(cu,float(i)*13.7));
                if(h>.95) continue;

                float W=max(.010,pixW*.75);
                float across=1.-smoothstep(W*.5,W*1.2,abs(fu)*CW);

                float spd=12.+h*10.;
                float y=p.y+cameraPosition.y+frameTimeCounter*spd+h*97.;
                const float SP=4.;
                float cy=floor(y/SP);
                float fy=(y-cy*SP);
                float h2=hash21(vec2(cu+float(i)*5.,cy));
                if(h2>.9) continue;
                float len=.8+h2*1.2;
                float along=smoothstep(len,0.,fy)*smoothstep(0.,.12,fy);

                streak+=across*along*mix(1.,.55,float(i)/7.)*min(1.,.02/W+.45);
            }
            float ra=clamp(streak,0.,1.)*rainAmt;
            if(ra>.002){
                float ev=texelFetch(samplerExposure,ivec2(0),0).r;
                float minLift=.16/(.0625*2.3*exp2(ev));
                vec3 rad=max(hdr,0.)*1.6+vec3(minLift)*vec3(.85,.92,1.);
                hdr=mix(hdr,rad,ra*.9);
                hdr+=rad*ra*.2;
            }
        }

        hdr*=exp2(texelFetch(samplerExposure,ivec2(0),0).r);

        color=vec4(AgX(hdr),c.a);
    }

#endif