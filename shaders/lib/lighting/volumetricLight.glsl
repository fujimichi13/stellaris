#ifndef VOLUMETRIC_LIGHT_GLSL
    #define VOLUMETRIC_LIGHT_GLSL a

    #include "/lib/utility/math.glsl"

    float rtwsmWarp1Dvec2(sampler2D lut,float u,int row)
    {
        if (u<=0||u>= 1.) return u;

        float t=u*256.;
        int i=min(int(t),255);
        float hi=texelFetch(lut,ivec2(i,row),0).r;
        if (hi<=0.) return u;

        float lo=(i==0)?0.:texelFetch(lut,ivec2(i-1,row),0).r;
        return mix(lo,hi,t-float(i));
    }

    vec3 visi(vec3 p)
    {
        vec4 sc=shadowProjection*(shadowModelView*vec4(p,1.));
        vec3 ndc=sc.xyz/sc.w;

        vec2 uv=vec2(rtwsmWarp1Dvec2(samplerWarpXY,ndc.x*.5+.5,0),rtwsmWarp1Dvec2(samplerWarpXY,ndc.y*.5+.5,1));
        float sz=ndc.z*.5+.5;

        if (any(lessThanEqual(uv,vec2(0.)))||any(greaterThanEqual(uv,vec2(1.)))||sz<=0.||sz>=1.)
            return vec3(1.);

        ivec2 res=textureSize(shadowtex1,0);
        ivec2 tc=clamp(ivec2(uv*vec2(res)),ivec2(0),res-1);

        float z=sz-.75*abs(shadowProjection[2][2])*.5;

        vec3 vis=vec3(1.);
        if (z>texelFetch(shadowtex1,tc,0).r){
            vis=vec3(0.);
        }
        #ifdef COLORED_SHADOW
            else if (z>texelFetch(shadowtex0,tc,0).r){
                vec3 tint=pow(texelFetch(shadowcolor0,tc,0).rgb,vec3(2.2));

                float mx=max(max(tint.r,tint.g),max(tint.b,1e-3));
                float mn=min(min(tint.r,tint.g),tint.b);

                vec3 hue=tint/mx;
                vec3 sat=(tint-mn)/max(mx-mn,1e-3);
                hue=mix(hue,sat,smoothstep(0.,.05,mx-mn));

                vis=mix(vec3(1.),hue,.85)*.85;
            }
        #endif

        float edge=max(abs(ndc.x),abs(ndc.y));
        return mix(vec3(1.),vis,1.-smoothstep(.85,1.,edge));
    }

    vec3 volumetricLight(vec3 dir,float rayLen,vec3 L,vec3 lightCol,vec3 ambient,float jitter,out vec3 T)
    {
        T=vec3(1.);

        float d=min(rayLen,128.);
        if (d<=.01) return vec3(0.);

        float cosT=dot(dir,L);
        float phaseM=mix(henyeyGreenstein(cosT,-.25),henyeyGreenstein(cosT,.76),.85);
        float phaseR=.0596831*(1.+cosT*cosT);

        float sigmaM=3.0e-4*VL_DENSITY*(1.+2.*rainStrength);

        ambient*=smoothstep(.1,.9,float(eyeBrightnessSmooth.y)/240.);

        vec3 acc=vec3(0.);
        float invN=1./float(VL_STEPS);

        for (int i=0;i<VL_STEPS;i++){
            float t0=d*pow(float(i)*invN,1.5);
            float t1=d*pow(float(i+1)*invN,1.5);
            float dt=t1-t0;

            vec3 p=dir*mix(t0,t1,jitter);

            float hAbove=max(cameraPosition.y+p.y-63.,0.0);
            float sM=sigmaM*exp(-hAbove/400.);
            vec3 sR=vec3(5.8e-6,13.5e-6,33.1e-6)*exp(-hAbove/8000.);

            vec3 sigmaS=sM+sR;
            vec3 sigmaT=sM*1.11+sR;

            vec3 vis=visi(p);

            vec3 S=(sM*phaseM+sR*phaseR)*lightCol*vis+sigmaS*ambient;

            vec3 stepT=exp(-sigmaT*dt);
            acc+=T*(S-S*stepT)/max(sigmaT,vec3(1e-8));
            T*=stepT;
        }

        return acc;
    }

#endif