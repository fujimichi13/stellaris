

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
    #include "/lib/utility/math.glsl"
    #include "/lib/utility/color.glsl"
    #include "/lib/utility/dithering.glsl"
    #include "/lib/utility/space.glsl"
    #include "/lib/atmosphere/scattering.glsl"
    #include "/lib/surface/brdf.glsl"
    #include "/lib/lighting/gtao.glsl"
    #include "/lib/lighting/volumetricLight.glsl"
    #include "/lib/atmosphere/volumetricClouds.glsl"
    #include "/lib/water/water.glsl"
    #include "/lib/water/waterFog.glsl"

    in vec2 texcoord;

    /* RENDERTARGETS:0 */
    layout(location=0) out vec4 color;

    int sur(ivec2 q,out vec3 n,out float rough){
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
        if(rough>=.6) return 0;
        n=normalize(nd.xyz);
        return 1;
    }

    vec4 reflectionFilter(ivec2 px,float depthC,int cls,vec3 nC,float roughC){
        vec4 rawC=texelFetch(colortex8,px,0);

        ivec2 res=ivec2(RRES);

        float radius=(cls==1)?mix(2.,7.,smoothstep(.05,.6,roughC)):2.5;
        radius*=float(1.);
        if(radius<.75) return rawC;

        vec3 Pc=viewSpacePosition((vec2(px)+.5)/RRES,depthC);
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
            vec3 Pq=viewSpacePosition((vec2(q)+.5)/RRES,dq);

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
        ivec2 px=ivec2(gl_FragCoord.xy);
        vec4 scene=texelFetch(colortex0,px,0);
        float depth=texelFetch(depthtex0,px,0).r;
        vec3 hdr=scene.rgb;

        vec4 nd=texelFetch(colortex3,px,0);

        if(depth<1.&&depth>=.56&&dot(nd.xyz,nd.xyz)>=.25&&abs(texelFetch(colortex13,px,0).w)<.5){
            vec3 N=normalize(nd.xyz);
            vec4 spec=texelFetch(colortex2,px,0);
            vec2 lm=texelFetch(colortex4,px,0).rg;

            vec3 albedoLin=pow(texelFetch(colortex7,px,0).rgb,vec3(2.2));
            Material m=decodeLabPBR(spec,albedoLin);
            m.ao=nd.w;
            #ifdef GTAO_ENABLED
                m.ao*=calcGTAO(px,albedoLin);
            #endif

            if(m.roughness<.6){
                vec3 P=viewSpacePosition(texcoord,depth);
                vec3 V=-normalize(mat3(gbufferModelViewInverse)*P);
                vec3 Rm=reflect(-V,N);

                vec4 hit=reflectionFilter(px,depth,1,N,m.roughness);
                hit.a*=1.-smoothstep(.6*.5,.6,m.roughness);

                if(hit.a>.001){
                    float skyVis=skyVisibility(lm.y);
                    vec3 skyDiff=skyRadiance(skyDiffuseDir(N))/**SKY_AMBIENT*/*skyVis*skyHemisphere(N);
                    vec3 R=doreflc(N,Rm,m.roughness);
                    vec3 skyEnv=skyRadiance(R);
                    #ifdef VOLUMETRIC_CLOUDS
                        if(m.roughness<.4&&skyVis>.01){
                            vec4 cl=volumetricClouds(R,CLOUD_REFLECTION_STEPS);
                            skyEnv=mix(skyEnv,skyEnv*(1.-cl.a)+cl.rgb,1.-smoothstep(.2,.4,m.roughness));
                        }
                    #endif
                    skyEnv=mix(skyEnv,skyDiff,m.roughness)*skyVis;
                    skyEnv*=mix(.15,1.,smoothstep(-.1,.05,R.y));

                    hdr+=evalAmbient(m,N,V,vec3(0.),(hit.rgb-skyEnv)*hit.a);
                }
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
            vec3 skyRefl=skyRadiance(R);
            #ifdef VOLUMETRIC_CLOUDS
                if(hit.a<.999&&skyVis>.01){
                    vec4 cl=volumetricClouds(R,CLOUD_REFLECTION_STEPS);
                    skyRefl=skyRefl*(1.-cl.a)+cl.rgb;
                }
            #endif
            skyRefl=(hit.a<.999)?skyRefl*skyVis:vec3(0.);
            vec3 refl=mix(skyRefl,hit.rgb,hit.a)*waterFresnel(NdotV);

            vec3 L=lightDirection();
            vec3 S=sunDirection();
            vec3 lightCol=lightColor(S);
            vec3 H=normalize(V+L);
            float NdotL=max(dot(N,L),0.);
            float NdotH=max(dot(N,H),0.);
            float a2=.0004+dot(P,P)*1e-7;
            float dd=NdotH*NdotH*(a2-1.)+1.;
            float k=.0032;
            float G=NdotL/(NdotL*(1.-k)+k)*NdotV/(NdotV*(1.-k)+k);
            float gl=waterFresnel(max(dot(V,H),0.))*a2/(3.14159265*dd*dd)*G/(4.*NdotV);
            refl+=lightCol*smoothstep(.8,1.,skyVis)*min(gl,40.);

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
            vec3 skyRefl=skyRadiance(R);
            #ifdef VOLUMETRIC_CLOUDS
                if(hit.a<.999&&skyVis>.01){
                    vec4 cl=volumetricClouds(R,CLOUD_REFLECTION_STEPS);
                    skyRefl=skyRefl*(1.-cl.a)+cl.rgb;
                }
            #endif
            skyRefl=(hit.a<.999)?skyRefl*skyVis*mix(.15,1.,smoothstep(-.1,.05,R.y)):vec3(0.);
            vec3 refl=mix(skyRefl,hit.rgb,hit.a)*F;

            vec3 L=lightDirection();
            vec3 S=sunDirection();
            vec3 lightCol=lightColor(S);
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

        #ifdef VOLUMETRIC_LIGHT
            if(isEyeInWater==0){
                vec3 Pv=viewSpacePosition(texcoord,depth);
                vec3 dir=normalize(mat3(gbufferModelViewInverse)*Pv);
                float rayLen=(depth<1.)?length(Pv):128.;

                vec3 L=lightDirection();
                vec3 S=sunDirection();
                vec3 lightCol=lightColor(S);
                vec3 ambient=.5*(skyRadiance(vec3(0.,1.,0.))+skyRadiance(normalize(vec3(dir.x,max(dir.y,.02),dir.z))));

                vec3 vlT;
                vec3 vlL=volumetricLight(dir,rayLen,L,lightCol,ambient,bluenoise(gl_FragCoord.xy+vec2(19.,41.)).x,vlT);
                hdr=hdr*vlT+vlL;
            }
        #endif

        if(isEyeInWater==1){
            vec3 Pv=viewSpacePosition(texcoord,depth);
            float dist=length(Pv);
            vec3 dir=normalize(mat3(gbufferModelViewInverse)*Pv);

            vec3 L=lightDirection();
            vec3 S=sunDirection();
            vec3 lightCol=lightColor(S);
            vec3 sky=skyAmbient();

            float camDepth=(1.-float(eyeBrightnessSmooth.y)/240.)*15.;

            if(depth<1.&&wn.w>.5){
                vec3 Ns=normalize(wn.xyz);
                float skyBehind=step(1.,texelFetch(depthtex1,px,0).r);
                float cosI=clamp(dot(-dir,Ns),0.,1.);
                float sinT2=1.333*1.333*(1.-cosI*cosI);
                float F=1.;
                vec3 T=vec3(0.);
                if(sinT2<1.){
                    float cosT=sqrt(1.-sinT2);
                    float rs=(1.333*cosI-cosT)/(1.333*cosI+cosT);
                    float rp=(1.333*cosT-cosI)/(1.333*cosT+cosI);
                    F=.5*(rs*rs+rp*rp);
                    T=normalize(refract(dir,Ns,1.333));
                }
                vec3 outside=hdr;
                if(F<1.&&skyBehind>.5){
                    float el=max(asin(clamp(T.y,-1.,1.)),0.);
                    outside=texture(samplerSky,vec2(atan(T.z,T.x)*.15915494+.5,sqrt(el*.63661977)*.5+.5)).rgb*(1.-.6*smoothstep(0.,-.4,T.y));
                    outside+=lightCol*smoothstep(.9998,.99985,dot(T,L))*smoothstep(-.02,0.,T.y)*30.;
                }
                vec3 inside=calcWaterFog(vec3(0.),reflect(dir,Ns),256.,0.,L,lightCol,sky);
                hdr=outside*(1.-F)+inside*F;
            }

            hdr=calcWaterFog(hdr,dir,dist,camDepth,L,lightCol,sky);

            if(L.y>=.02){
                vec3 sigS=vec3(WATER_FOG_SCATTERING);
                vec3 sigT=vec3(.45,.07,.012)*WATER_FOG_DENSITY+sigS;

                float cosL=sqrt(1.-(1.-L.y*L.y)/1.7778);
                float sinL=sqrt(max(1.-cosL*cosL,0.));
                float Fr=.02+.98*pow(1.-L.y,5.);
                vec3 sunE=lightCol*(1.-Fr)*L.y/cosL;
                float phase=.4375/(12.5663706*pow(1.5625-1.5*dot(L,dir),1.5));

                float d=(dir.y>1e-3)?min(dist,camDepth/dir.y):dist;
                d=min(d,3./min(sigT.x,min(sigT.y,sigT.z)));
                float dt=d/20.;

                float jitter=bluenoise(gl_FragCoord.xy+vec2(53.,7.)).x;
                vec2 Lh=L.xz/max(length(L.xz),1e-4);
                vec2 shadowRes=vec2(textureSize(shadowtex1,0));
                float zBias=.75*abs(shadowProjection[2][2])*.5;

                vec3 acc=vec3(0.);
                for(int i=0;i<20;i++){
                    float t=(float(i)+jitter)*dt;
                    vec3 p=dir*t;
                    float wd=max(camDepth-dir.y*t,0.);

                    vec4 sc=shadowProjection*(shadowModelView*vec4(p,1.));
                    vec3 ndc=sc.xyz/sc.w;
                    vec2 suv=ndc.xy*.5+.5;
                    vec2 wuv=suv;
                    if(suv.x>0.&&suv.x<1.){
                        float tx=suv.x*256.;
                        int ix=min(int(tx),255);
                        float hx=texelFetch(samplerWarpXY,ivec2(ix,0),0).r;
                        if(hx>0.) wuv.x=mix((ix==0)?0.:texelFetch(samplerWarpXY,ivec2(ix-1,0),0).r,hx,tx-float(ix));
                    }
                    if(suv.y>0.&&suv.y<1.){
                        float ty=suv.y*256.;
                        int iy=min(int(ty),255);
                        float hy=texelFetch(samplerWarpXY,ivec2(iy,1),0).r;
                        if(hy>0.) wuv.y=mix((iy==0)?0.:texelFetch(samplerWarpXY,ivec2(iy-1,1),0).r,hy,ty-float(iy));
                    }

                    float vis=1.;
                    float sz=ndc.z*.5+.5;
                    if(all(greaterThan(wuv,vec2(0.)))&&all(lessThan(wuv,vec2(1.)))&&sz>0.&&sz<1.){
                        float sd=texelFetch(shadowtex1,clamp(ivec2(wuv*shadowRes),ivec2(0),ivec2(shadowRes)-1),0).r;
                        vis=(sz-zBias>sd)?0.:1.;
                        vis=mix(1.,vis,1.-smoothstep(.85,1.,max(abs(ndc.x),abs(ndc.y))));
                    }

                    vec2 entry=cameraPosition.xz+p.xz+Lh*(sinL*wd/cosL);
                    float wn2=.6*texture(noisetex,fract(entry*.035+frameTimeCounter*vec2(.02,.012))).z
                             +.4*texture(noisetex,fract(entry*.11-frameTimeCounter*vec2(.03,.01)+.37)).z;
                    float focus=mix(1.,2.*smoothstep(.3,.7,wn2),.6);

                    acc+=exp(-sigT*(wd/cosL+t))*(vis*focus-1.);
                }

                hdr=max(hdr+sigS*sunE*phase*acc*dt,0.);
            }
        }

        color=vec4(hdr,1.);
    }

#endif