
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
    #include "/lib/utility/dithering.glsl"
    #include "/lib/utility/space.glsl"
    #include "/lib/atmosphere/scattering.glsl"
    #include "/lib/surface/brdf.glsl"
    #include "/lib/lighting/gtao.glsl"
    #include "/lib/atmosphere/volumetricClouds.glsl"

    layout(r32ui) uniform uimage2D histXY;

    #ifdef VOLUMETRIC_CLOUDS
        layout(rgba32f) uniform image2D cloudHistA;
        layout(rgba32f) uniform image2D cloudHistB;

        vec3 cldCompress(vec3 c){
            return c/(1.+dot(c,vec3(.2126,.7152,.0722)));
        }
        vec3 cldDecompress(vec3 c){
            return c/max(1.-dot(c,vec3(.2126,.7152,.0722)),1e-4);
        }

        vec4 cloudHistFetch(ivec2 q,bool readA){
            vec4 h=readA?texelFetch(samplerCloudHistA,q,0):texelFetch(samplerCloudHistB,q,0);
            if(any(isnan(h))) h=vec4(0.);
            return h;
        }

        void cloudHistStore(ivec2 q,vec4 v,bool writeA){
            if(writeA) imageStore(cloudHistA,q,v); else imageStore(cloudHistB,q,v);
        }

        vec2 cloudPrevUV(vec3 rd,out bool valid){
            float ry=rd.y<0.?min(rd.y,-.05):max(rd.y,.05);
            float t=clamp(((CLOUD_ALTITUDE*(1.-.3*saturate(cloudRain))+max(CLOUD_THICKNESS*(1.+.25*saturate(cloudRain)),1.)*.5)-cameraPosition.y)/ry,0.,1e8);
            vec2 wd=vec2(1.,.35)*frameTime*CLOUD_WIND_SPEED;
            vec3 wp=rd*t+(cameraPosition-previousCameraPosition)-vec3(wd.x,0.,wd.y);
            vec4 pc=gbufferPreviousProjection*(gbufferPreviousModelView*vec4(wp,1.));
            valid=pc.w>0.;
            return pc.xy/max(abs(pc.w),1e-5)*.5+.5;
        }

        vec4 cloudTemporal(vec4 cur,vec3 rd,ivec2 px,vec2 uv,bool fresh){
            bool writeA=(frameCounter&1)==0;
            vec2 rr=RRES;

            bool pv;
            vec2 prevUV=cloudPrevUV(rd,pv);
            bool ok=pv&&all(greaterThan(prevUV,vec2(0.)))&&all(lessThan(prevUV,vec2(1.)));

            float stretch=0.;
            if(ok){
                vec2 px1=(vec2(px)+vec2(1.5,.5))/rr;
                vec2 py1=(vec2(px)+vec2(.5,1.5))/rr;
                bool v1,v2;
                vec2 ux=cloudPrevUV(normalize(worldSpacePosition(px1,1.)),v1);
                vec2 uy=cloudPrevUV(normalize(worldSpacePosition(py1,1.)),v2);
                vec2 dx=(ux-prevUV)*rr;
                vec2 dy=(uy-prevUV)*rr;
                stretch=abs(length(dx)-1.)+abs(length(dy)-1.)+abs(dot(dx,dy));
            }

            vec3 curC=cldCompress(cur.rgb);
            float n=0.;
            vec3 outC=curC;
            float outA=cur.a;

            if(ok){
                vec2 pos=prevUV*rr-.5;
                ivec2 b=ivec2(floor(pos));
                vec2 f=pos-vec2(b);
                bool readA=!writeA;

                vec4 acc=vec4(0.);
                float nAcc=0.,wAcc=0.;
                for(int i=0;i<4;i++){
                    ivec2 o=ivec2(i&1,i>>1);
                    ivec2 q=b+o;
                    if(any(lessThan(q,ivec2(0)))||any(greaterThanEqual(q,ivec2(rr)))) continue;
                    vec4 h=cloudHistFetch(q,readA);
                    if(h.a<0.) continue;
                    float w=((o.x==0)?1.-f.x:f.x)*((o.y==0)?1.-f.y:f.y);
                    float hn=floor(h.a);
                    float ha=clamp(fract(h.a)/.999,0.,1.);
                    acc+=vec4(h.rgb,ha)*w;
                    nAcc+=hn*w;
                    wAcc+=w;
                }

                if(wAcc>.75){
                    vec4 hist=acc/wAcc;
                    float hn=floor(nAcc/wAcc+.5);

                    float motion=length((prevUV-uv)*rr);
                    if(fresh) hn*=1.-smoothstep(.15,3.,motion);
                    hn*=1.-smoothstep(.015,.12,stretch);
                    hn*=smoothstep(.75,1.,wAcc);
                    hn=min(hn,32.-1.);
                    #if CLOUD_UPSCALING>0
                        if(fresh) hn=max(hn,1.5*smoothstep(.75,1.,wAcc));
                    #endif

                    float lc=dot(curC,vec3(.2126,.7152,.0722));
                    float lh=dot(hist.rgb,vec3(.2126,.7152,.0722));
                    float diff=abs(lc-lh)+abs(cur.a-hist.a)*.5;
                    if(fresh) hn*=1.-smoothstep(.25,.7,diff)*.75;

                    float w=fresh?hn/(hn+1.):1.;
                    outC=mix(curC,hist.rgb,w);
                    outA=mix(cur.a,hist.a,w);
                    n=floor((fresh?hn+1.:max(hn,1.))+.5);
                }
            }

            #if CLOUD_UPSCALING>0
                if(ok){
                    float conf=n/(n+3.);
                    if(conf<.9){
                        ivec2 c0=ivec2(floor(prevUV*rr));
                        bool readA2=!writeA;
                        vec4 bsum=vec4(0.);
                        float bw=0.;
                        for(int i=0;i<5;i++){
                            ivec2 o=(i==0)?ivec2(0):((i==1)?ivec2(1,0):((i==2)?ivec2(-1,0):((i==3)?ivec2(0,1):ivec2(0,-1))));
                            ivec2 q=c0+o;
                            if(any(lessThan(q,ivec2(0)))||any(greaterThanEqual(q,ivec2(rr)))) continue;
                            vec4 h=cloudHistFetch(q,readA2);
                            if(h.a<1.) continue;
                            float kw=(i==0)?2.:1.;
                            bsum+=vec4(h.rgb,clamp(fract(h.a)/.999,0.,1.))*kw;
                            bw+=kw;
                        }
                        if(bw>2.5){
                            vec4 blur=bsum/bw;
                            float a=(1.-conf)*.65;
                            outC=mix(outC,blur.rgb,a);
                            outA=mix(outA,blur.a,a);
                        }
                    }
                }
            #endif

            cloudHistStore(px,vec4(outC,min(floor(n),32.)+clamp(outA,0.,1.)*.999),writeA);
            return vec4(cldDecompress(outC),outA);
        }
    #endif

    in vec2 texcoord;

    /* RENDERTARGETS:8,7 */
    layout(location=0) out vec4 color;
    layout(location=1) out vec4 color1;

    const float sunPathRotation=-40.0;

    const int shadowMapResolution=2048;
    const float shadowDistance=192.0;

    float rtwsmWarp1D(sampler2D tex,float u,int row,out float slope){
        slope=1.;
        if(u<=0.||u>=1.) return u;

        float t=u*float(256);
        int i=min(int(t),256-1);
        float f=t-float(i);

        float hi=texelFetch(tex,ivec2(i,row),0).r;
        if(hi<=0.) return u;

        float lo=(i==0)?0.:texelFetch(tex,ivec2(i-1,row),0).r;

        slope=max((hi-lo)*float(256),1e-3);
        return mix(lo,hi,f);
    }

    vec2 rtwsmWarp(vec2 clipXY,out vec2 slope){
        vec2 uv=clipXY*.5+.5;
        vec2 w;
        w.x=rtwsmWarp1D(samplerWarpXY,uv.x,0,slope.x);
        w.y=rtwsmWarp1D(samplerWarpXY,uv.y,1,slope.y);
        return w*2.-1.;
    }

    vec4 toShadowClip(vec3 worldPos){
        vec4 c=shadowProjection*(shadowModelView*vec4(worldPos,1.));
        return vec4(c.xyz/c.w,1.);
    }

    vec3 sampleShadow(vec3 worldPos,vec3 n,float NdotL){
        vec4 clip=toShadowClip(worldPos);

        vec2 slope;
        rtwsmWarp(clip.xy,slope);
        vec2 texelWorld=vec2(abs(2./shadowProjection[0][0]),abs(2./shadowProjection[1][1]))/(float(shadowMapResolution)*slope);
        float texel=max(texelWorld.x,texelWorld.y);

        float sinT=sqrt(max(1.-NdotL*NdotL,0.));
        float tanT=min(sinT/max(NdotL,.05),4.);

        //vec3 offsetPos=worldPos+n*texel*1.*(.5+sinT);
        vec3 offsetPos=worldPos+n*texel*1.5*(.5+sinT);

        vec4 c=toShadowClip(offsetPos);
        vec2 sampleSlope;
        vec2 warpedXY=rtwsmWarp(c.xy,sampleSlope);
        vec3 sp=vec3(warpedXY,c.z)*.5+.5;

        if(sp.x<0.||sp.x>1.||sp.y<0.||sp.y>1.||sp.z<0.||sp.z>1.){
            return vec3(1.);
        }

        vec2 ortho=vec2(abs(2./shadowProjection[0][0]),abs(2./shadowProjection[1][1]));
        float depthRange=2./abs(shadowProjection[2][2]);

        vec2 sampleTexelWorld=ortho/(float(shadowMapResolution)*sampleSlope);
        float sampleTexel=max(sampleTexelWorld.x,sampleTexelWorld.y);

        float zBias=sampleTexel*(.25+1.*tanT)*abs(shadowProjection[2][2])*.5;
        float z=sp.z-zBias;

        float texelUV=1./float(shadowMapResolution);
        vec2 bn=bluenoiseStatic(gl_FragCoord.xy)*TAU;

        //blocker
        vec2 searchUV=min(depthRange*.0047*sampleSlope/ortho,vec2(64.*texelUV));
        float searchBias=.0025*min(tanT,1.5);
        float blockerSum=0.;
        float blockers=0.;
        for(int i=0;i<8;i++){
            float a=float(i)*2.3999632+bn.x;
            vec2 p=sqrt((float(i)+.5)/8.)*vec2(cos(a),sin(a));
            float d=texture(shadowtex1,sp.xy+p*searchUV).r;
            if(d<z-length(p)*searchBias){
                blockerSum+=d;
                blockers+=1.;
            }
        }

        //penumbra
        float avgBlocker=(blockers>.5)?blockerSum/blockers:z;
        float penumbraWorld=(z-avgBlocker)*depthRange*.0047;
        vec2 filterUV=max(penumbraWorld*sampleSlope/ortho,vec2(1.5*texelUV));

        // filter
        float radiusBias=penumbraWorld*tanT*abs(shadowProjection[2][2])*.25;
        vec3 visSum=vec3(0.);
        for(int i=0;i<12;i++){
            float a=float(i)*2.3999632+bn.y;
            vec2 p=sqrt((float(i)+.5)/12.)*vec2(cos(a),sin(a));
            vec2 suv=sp.xy+p*filterUV;
            float zs=z-length(p)*radiusBias;

            if(zs>texture(shadowtex1,suv).r){
                continue;
            }

            vec3 v=vec3(1.);
            #ifdef COLORED_SHADOW
                if(zs>texture(shadowtex0,suv).r){
                    vec3 tint=pow(texture(shadowcolor0,suv).rgb,vec3(2.2));

                    float mx=max(max(tint.r,tint.g),max(tint.b,1e-3));
                    float mn=min(min(tint.r,tint.g),tint.b);

                    vec3 hue=tint/mx;
                    vec3 sat=(tint-mn)/max(mx-mn,1e-3);
                    hue=mix(hue,sat,smoothstep(0.,.05,mx-mn));

                    v=mix(vec3(1.),hue,.85)*.85;
                }
            #endif
            visSum+=v;
        }
        vec3 vis=visSum/12.;

        float edge=max(abs(clip.x),abs(clip.y));
        float fade=1.-smoothstep(.85,1.,edge);

        return mix(vec3(1.),vis,fade);
    }
    
    void main(){
        ivec2 px=ivec2(gl_FragCoord.xy);
        vec4 albedo=texelFetch(colortex0,px,0);
        float depth=texelFetch(depthtex0,px,0).r;
        if(abs(texelFetch(colortex13,px,0).w)>.5) depth=texelFetch(depthtex1,px,0).r;
        bool isHand=depth<.56;
        if(isHand) depth=((depth*2.-1.)/.125)*.5+.5;

        color=albedo;
        color1=vec4(0.,0.,0.,1.);
        if(depth>=1.){
            #ifdef VOLUMETRIC_CLOUDS
                vec3 cloudDir=normalize(worldSpacePosition(texcoord,1.));

                bool fresh=true;
                #if CLOUD_UPSCALING>0
                    {
                        #if CLOUD_UPSCALING==2
                            bool myTurn=((px.x+px.y+frameCounter)&1)==0;
                        #else
                            const int bayerOrder[4]=int[4](0,3,1,2);
                            bool myTurn=((px.x&1)+((px.y&1)<<1))==bayerOrder[frameCounter&3];
                        #endif

                        if(!myTurn){
                            vec2 rr=RRES;
                            bool pv;
                            vec2 pUV=cloudPrevUV(cloudDir,pv);
                            bool pOk=pv&&all(greaterThan(pUV,vec2(0.)))&&all(lessThan(pUV,vec2(1.)));

                            if(pOk&&length((pUV-texcoord)*rr)<4.){
                                vec2 hp=pUV*rr-.5;
                                ivec2 hb=ivec2(floor(hp));
                                bool readA=(frameCounter&1)!=0;
                                bool good=true;
                                for(int i=0;i<4;i++){
                                    ivec2 hq=hb+ivec2(i&1,i>>1);
                                    if(any(lessThan(hq,ivec2(0)))||any(greaterThanEqual(hq,ivec2(rr)))){ good=false; break; }
                                    vec4 hh=cloudHistFetch(hq,readA);
                                    if(hh.a<1.){ good=false; break; }
                                }
                                fresh=!good;
                            }
                        }
                    }
                #endif

                vec4 cl=fresh?volumetricClouds(cloudDir,CLOUD_RAY_STEPS):vec4(0.);
                cl=cloudTemporal(cl,cloudDir,px,texcoord,fresh);
                vec3 sunS=sunDirection();
                vec3 sunC=vec3(0.);
                float sunD=smoothstep(.9998,.99985,dot(cloudDir,sunS));
                if(sunD>0.){
                    float sunAlt=eyeAlt(cameraPosition.y);
                    if(sunAlt>50.){
                        vec4 sunT;
                        float sunG;
                        calcInscattering(vec3(0.,R+sunAlt,0.),cloudDir,sunS,samplerTransmittance,sunT,sunG);
                        sunC=toRGB(sunIrr*sunT)*sunD*(sunG<0.?1.:0.)*30.;
                    }else{
                        sunC=toRGB(sunIrr*lutT(samplerTransmittance,sunS.y,sunAlt*.01))*sunD*smoothstep(-.02,0.,cloudDir.y)*30.;
                    }
                }
                float sunTr=pow(1.-cl.a,6.)*(1.-smoothstep(.2,.8,saturate(cloudRain)));
                color=vec4(max(albedo.rgb-sunC,0.)*(1.-cl.a)+cl.rgb+sunC*sunTr,albedo.a);
            #endif
            return;
        }
        #ifdef VOLUMETRIC_CLOUDS
            cloudHistStore(px,vec4(0.,0.,0.,-1.),(frameCounter&1)==0);
        #endif

        vec3 worldPos=worldSpacePosition(texcoord,depth);

        vec3 gc=cross(dFdx(worldPos),dFdy(worldPos));
        vec3 ng=gc/max(length(gc),1e-8);
        if(dot(ng,worldPos)>0.) ng=-ng;

        vec3 L=lightDirection();
        float NdotLg=clamp(dot(ng,L),0.,1.);

        vec4 shadowClip=toShadowClip(worldPos);
        vec2 suv=shadowClip.xy*.5+.5;
        if(!isHand&&((px.x&3)|(px.y&3))==0&&suv.x>=0.&&suv.x<=1.&&suv.y>=0.&&suv.y<=1.){
            int binX=clamp(int(suv.x*float(256)),0,256-1);
            int binY=clamp(int(suv.y*float(256)),0,256-1);
            imageAtomicAdd(histXY,ivec2(binX,0),1u);
            imageAtomicAdd(histXY,ivec2(binY,1),1u);
        }

        uvec4 gbPx=texelFetch(colortex3,px,0);

        vec3 visC=vec3(smoothstep(.3,.9,gbUnpackLM(gbPx).y));
        if(!isHand) visC=sampleShadow(worldPos,ng,NdotLg);

        vec4 nd=gbPresent(gbPx)?vec4(gbUnpackNormal(gbPx),float(gbPx.z>>24)*(1./255.)):vec4(0.);
        if(dot(nd.xyz,nd.xyz)<.25){
            color=vec4(albedo.rgb*mix(vec3(.35),vec3(1.),visC),albedo.a);
            return;
        }

        vec3 N=normalize(nd.xyz);
        vec2 lm=gbUnpackLM(gbPx);

        vec3 albedoLin=pow(albedo.rgb,vec3(2.2));
        Material m=gbUnpack(gbPx,albedoLin);

        #ifdef GTAO_ENABLED
            m.ao*=calcGTAO(px,albedoLin);
        #endif

        vec3 V=-normalize(worldPos);

        vec3 lightCol=lightColor(sunDirection());

        vec3 vis2=visC*smoothstep(0.,.1,NdotLg);
        vis2=mix(vis2,visC*.5,m.sss*step(NdotLg,.001));

        vec3 dDiff,dSpec;
        evalDirectBRDF(m,N,V,L,dDiff,dSpec);
        vec3 direct=(dDiff+dSpec)*lightCol*vis2;

        {
            float cH=0.;
            float wnw=texelFetch(colortex13,px,0).w;
            if(isEyeInWater==1){
                cH=(1.-float(eyeBrightnessSmooth.y)/240.)*15.-worldPos.y;
            }else if(wnw>.5){
                cH=worldSpacePosition(texcoord,texelFetch(depthtex0,px,0).r).y-worldPos.y;
            }
            if(cH>0.&&L.y>=.05){
                float cosL=sqrt(1.-(1.-L.y*L.y)/1.7778);
                float tanL=sqrt(max(1.-cosL*cosL,0.))/cosL;
                vec2 Lh=L.xz/max(length(L.xz),1e-4);
                vec2 cp=worldPos.xz+cameraPosition.xz+Lh*(tanL*cH);
                float cts=CAUSTICS_MAP_BLOCKS/float(CAUSTICS_MAP_RES);
                vec2 cuv=(cp-(floor(cameraPosition.xz/cts)*cts-.5*CAUSTICS_MAP_BLOCKS))/CAUSTICS_MAP_BLOCKS;
                float cedge=min(min(cuv.x,1.-cuv.x),min(cuv.y,1.-cuv.y));
                if(cedge>0.){
                    vec4 A=textureLod(samplerCaustic,cuv,0.);
                    float det=(1.+cH*A.x)*(1.+cH*A.w)-cH*cH*A.y*A.z;
                    float cc=sqrt(1.0225/(det*det+.0225));
                    direct*=mix(1.,cc,(1.-smoothstep(12.,32.,cH))*smoothstep(0.,.1,cedge));
                }
            }
        }

        float skyVis=skyVisibility(lm.y);
        vec3 skyDiff=skyRadiance(skyDiffuseDir(N))*1.*skyVis*skyHemisphere(N);
        vec3 R=doreflc(N,reflect(-V,N),m.roughness);
        vec3 skyEnv=skyRadiance(R);
        #ifdef VOLUMETRIC_CLOUDS
            if(m.roughness<.4&&skyVis>.01){
                vec4 cl=volumetricClouds(R,CLOUD_REFLECTION_STEPS);
                skyEnv=mix(skyEnv,skyEnv*(1.-cl.a)+cl.rgb,1.-smoothstep(.2,.4,m.roughness));
            }
        #endif
        skyEnv=mix(skyEnv,skyDiff,m.roughness)*skyVis;
        skyEnv*=mix(.15,1.,smoothstep(-.1,.05,R.y));
        vec3 ambient=evalAmbient(m,N,V,vec3(0.),skyEnv);

        vec3 sa=specalbedo(m,max(dot(N,V),1e-3));
        float specW=idrspecweight(m.roughness);

        vec3 emissive=m.albedo*m.emission*16.;

        color1=vec4(m.diffuse*nd.w,0.);
        
        vec3 wf=m.diffuse*vec3(1.,.62,.32)*.025*m.ao;

        vec3 hdr=direct+ambient+emissive+wf;
        color=vec4(hdr,albedo.a);
    }

#endif