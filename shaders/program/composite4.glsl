

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
    #include "/lib/surface/brdf.glsl"
    #include "/lib/lighting/gtao.glsl"

    in vec2 texcoord;

    /* RENDERTARGETS:0 */
    layout(location = 0) out vec4 color;

    vec2 bluenoise(vec2 fragCoord){
        vec2 b=texelFetch(noisetex,ivec2(fragCoord)&127,0).rg;
        #ifdef TAA_ENABLED
            b=fract(b+float(frameCounter&63)*vec2(.7548777,.5698403));
        #endif
        return b;
    }

    vec3 viewSpacePosition(vec2 uv, float depth){
        vec4 v=gbufferProjectionInverse*vec4(uv*2.-1.,depth*2.-1.,1.);
        return v.xyz/v.w;
    }

    vec3 skyRadiance(vec3 d){
        float t=max(asin(clamp(d.y,-1.,1.)),0.);
        vec3 s=texture(samplerSky,vec2(atan(d.z,d.x)*.15915494+.5,sqrt(t*.63661977)*.5+.5)).rgb;
        return s*(1.-.6*smoothstep(0.,-.4,d.y));
    }

    //https://github.com/TheRealMJP/BakingLab/blob/master/BakingLab/ACES.hlsl
    vec3 ACES(vec3 v){
        v=mat3(.59719,.0760,.0284,.35458,.90834,.13383,.04823,.01566,.83777)*max(v,0.)*.0625;
        v=(v*(v+.0245786)-.000090537)/(v*(.983729*v+.432951)+.238081);
        return clamp(mat3(1.60475,-.10208,-.00327,-.53108,1.10813,-.07276,-.07367,-.00605,1.07602)*v,0.,1.);
    }

    #include "/lib/atmosphere/scattering.glsl"
    #include "/lib/water/water.glsl"    

    int sur(ivec2 q, out vec3 n, out float rough){
        n=vec3(0.);
        rough=0.;
        if(texelFetch(depthtex0,q,0).r>=1.) return 0;

        vec4 w=texelFetch(colortex13,q,0);
        if(w.w>.5){
            if(isEyeInWater!=0) return 0;
            n=normalize(w.xyz);
            return 2;
        }
        if(w.w<-.5){
            n=normalize(w.xyz);
            return 3;
        }

        vec4 nd=texelFetch(colortex3,q,0);
        if(dot(nd.xyz,nd.xyz)<.25) return 0;
        float sr=texelFetch(colortex2,q,0).r;
        rough=max((1.-sr)*(1.-sr),.045);
        if(rough>=.4) return 0;
        n=normalize(nd.xyz);
        return 1;
    }

    vec4 reflectionFilter(ivec2 px, float depthC, int cls, vec3 nC, float roughC){
        vec4 rawC=texelFetch(colortex8,px,0);

        ivec2 res=ivec2(viewWidth,viewHeight);

        float radius=(cls==1)?mix(2.,7.,smoothstep(.05,.4,roughC)):2.5;
        radius*=float(1.);
        if(radius<.75) return rawC;

        vec3 Pc=viewSpacePosition((vec2(px)+.5)/vec2(res),depthC);
        vec3 nv=normalize(mat3(gbufferModelView)*nC);
        float zc=-Pc.z;

        float lw0=1./(1.+dot(rawC.rgb,vec3(.3333333)));
        vec3 rgbAcc=rawC.rgb*(rawC.a*lw0);
        float rgbW=rawC.a*lw0;
        float aAcc=rawC.a;
        float wsum=1.;

        vec2 bn=bluenoise(gl_FragCoord.xy+vec2(91.,13.));
        const int TAPS=12;
        for(int i=0;i<TAPS;i++){
            float ang=(float(i)+bn.x)*2.3999632;
            float r=sqrt((float(i)+.5)/float(TAPS))*radius;
            ivec2 q=px+ivec2(round(vec2(cos(ang),sin(ang))*r));
            if(any(lessThan(q,ivec2(0)))||any(greaterThanEqual(q,res))||all(equal(q,px))) continue;

            vec3 nq;
            float rq;
            if(sur(q,nq,rq)!=cls) continue;

            float dq=texelFetch(depthtex0,q,0).r;
            vec3 Pq=viewSpacePosition((vec2(q)+.5)/vec2(res),dq);

            float w=exp(-abs(dot(Pq-Pc,nv))/(.02*zc+.02));
            w*=pow(max(dot(nC,nq),0.),16.);
            w*=exp(-abs(rq-roughC)*12.);
            float f=r/radius;
            w*=exp(-1.5*f*f);
            if(w<1e-4) continue;

            vec4 s=texelFetch(colortex8,q,0);
            float lw=1./(1.+dot(s.rgb,vec3(.3333333)));
            rgbAcc+=s.rgb*(s.a*w*lw);
            rgbW+=s.a*w*lw;
            aAcc+=s.a*w;
            wsum+=w;
        }

        return vec4(rgbAcc/max(rgbW,1e-5),aAcc/wsum);
    }

    float waterFresnel(float cosI){
        float c=clamp(cosI,0.,1.);
        float sinT2=(1.-c*c)/(1.333*1.333);
        float cosT=sqrt(max(1.-sinT2,0.));
        float rs=(c-1.333*cosT)/(c+1.333*cosT);
        float rp=(1.333*c-cosT)/(1.333*c+cosT);
        return .5*(rs*rs+rp*rp);
    }

    void main(){
        vec4 scene=texture(colortex0,texcoord);
        float depth=texture(depthtex0,texcoord).r;
        vec3 hdr=scene.rgb;

        ivec2 px=ivec2(gl_FragCoord.xy);
        vec4 nd=texelFetch(colortex3,px,0);

        if(depth<1.&&dot(nd.xyz,nd.xyz)>=.25&&abs(texelFetch(colortex13,px,0).w)<.5){
            vec3 N=normalize(nd.xyz);
            vec4 spec=texelFetch(colortex2,px,0);
            vec2 lm=texelFetch(colortex4,px,0).rg;

            vec3 albedoLin=pow(texelFetch(colortex7,px,0).rgb,vec3(2.2));
            Material m=decodeLabPBR(spec,albedoLin);
            m.ao=nd.w;
            #ifdef GTAO_ENABLED
                m.ao*=calcGTAO(px,albedoLin);
            #endif

            if(m.roughness<.4){
                vec3 P=viewSpacePosition(texcoord,depth);
                vec3 V=-normalize(mat3(gbufferModelViewInverse)*P);
                vec3 Rm=reflect(-V,N);

                vec4 hit=reflectionFilter(px,depth,1,N,m.roughness);
                hit.a*=1.-smoothstep(.4*.5,.4,m.roughness);

                //float skyVis=lm.y*lm.y;
                float skyVis=skyVisibility(lm.y);
                vec3 skyDiff=skyRadiance(skyDiffuseDir(N))/**SKY_AMBIENT*/*skyVis*skyHemisphere(N);
                vec3 R=doreflc(N,Rm,m.roughness);
                vec3 skyEnv=mix(skyRadiance(R),skyDiff,m.roughness)*skyVis;
                skyEnv*=mix(.15,1.,smoothstep(-.1,.05,R.y));

                hdr+=evalAmbient(m,N,V,vec3(0.),(hit.rgb-skyEnv)*hit.a);
            }
        }

        vec4 wn=texelFetch(colortex13,px,0);
        if(depth<1.&&wn.w>.5&&isEyeInWater==0){
            vec3 N=normalize(wn.xyz);
            vec3 P=viewSpacePosition(texcoord,depth);
            vec3 V=-normalize(mat3(gbufferModelViewInverse)*P);
            float NdotV=max(dot(N,V),.001);

            vec3 R=reflect(-V,N);
            R.y=abs(R.y);
            vec4 hit=reflectionFilter(px,depth,2,N,0.);

            float skyVis=texelFetch(colortex14,px,0).a;
            skyVis*=skyVis;
            vec3 refl=mix(skyRadiance(R)*skyVis,hit.rgb,hit.a)*waterFresnel(NdotV);

            vec3 L=normalize(mat3(gbufferModelViewInverse)*shadowLightPosition);
            vec3 S=normalize(mat3(gbufferModelViewInverse)*sunPosition);
            vec3 lightCol=toRGB(sunIrr*lutT(samplerTransmittance,S.y,eyeAlt(cameraPosition.y)*.01))*smoothstep(-.04,.0,S.y)+vec3(.20,.30,.55)*.35*(1.-smoothstep(-.12,.02,S.y));
            vec3 H=normalize(V+L);
            float NdotL=max(dot(N,L),0.);
            float NdotH=max(dot(N,H),0.);
            float a2=.0000410;
            float dd=NdotH*NdotH*(a2-1.)+1.;
            float k=.0032;
            float G=NdotL/(NdotL*(1.-k)+k)*NdotV/(NdotV*(1.-k)+k);
            refl+=lightCol*smoothstep(.8,1.,skyVis)*waterFresnel(max(dot(V,H),0.))*a2/(3.14159265*dd*dd)*G/(4.*NdotV);

            hdr+=refl;
        }

        if(depth<1.&&wn.w<-.5){
            vec3 N=normalize(wn.xyz);
            vec3 P=viewSpacePosition(texcoord,depth);
            vec3 V=-normalize(mat3(gbufferModelViewInverse)*P);
            float NdotV=max(dot(N,V),.001);
            float c5=1.-NdotV;
            float F=.04+.96*c5*c5*c5*c5*c5;

            vec3 R=reflect(-V,N);
            vec4 hit=reflectionFilter(px,depth,3,N,0.);

            float skyVis=skyVisibility(fract(-wn.w)/.99);
            vec3 skyRefl=skyRadiance(R)*skyVis*mix(.15,1.,smoothstep(-.1,.05,R.y));
            vec3 refl=mix(skyRefl,hit.rgb,hit.a)*F;

            vec3 L=normalize(mat3(gbufferModelViewInverse)*shadowLightPosition);
            vec3 S=normalize(mat3(gbufferModelViewInverse)*sunPosition);
            vec3 lightCol=toRGB(sunIrr*lutT(samplerTransmittance,S.y,eyeAlt(cameraPosition.y)*.01))*smoothstep(-.04,.0,S.y)+vec3(.20,.30,.55)*.35*(1.-smoothstep(-.12,.02,S.y));
            vec3 H=normalize(V+L);
            float NdotL=max(dot(N,L),0.);
            float NdotH=max(dot(N,H),0.);
            float a2=.0000410;
            float dd=NdotH*NdotH*(a2-1.)+1.;
            float k=.0032;
            float G=NdotL/(NdotL*(1.-k)+k)*NdotV/(NdotV*(1.-k)+k);
            float cvh=1.-max(dot(V,H),0.);
            float Fh=.04+.96*cvh*cvh*cvh*cvh*cvh;
            refl+=lightCol*smoothstep(.8,1.,skyVis)*Fh*a2/(3.14159265*dd*dd)*G/(4.*NdotV);

            hdr+=refl;
        }

        color=vec4(hdr,1.);
    }

#endif