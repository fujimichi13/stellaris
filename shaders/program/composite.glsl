

#ifdef vsh

    out vec2 texcoord;

    void main(){
        gl_Position=ftransform();
        texcoord=(gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;
    }

#endif

#ifdef fsh

    layout(rgba16f) uniform image2D cloudHistA;
    layout(rgba16f) uniform image2D cloudHistB;

    #include "/settings.glsl"
    #include "/lib/utility/uniforms.glsl"
    #include "/lib/utility/math.glsl"
    #include "/lib/utility/dithering.glsl"
    #include "/lib/utility/space.glsl"
    #include "/lib/utility/color.glsl"
    #include "/lib/atmosphere/scattering.glsl"
    #include "/lib/surface/brdf.glsl"
    #include "/lib/lighting/gtao.glsl"
    #include "/lib/atmosphere/volumetricClouds.glsl"

    /*
    const int colortex3Format = RGBA16F;
    const int colortex7Format = RGBA16F;
    const int colortex8Format = RGBA16F;

    const bool shadowtex0Nearest = true;
    const bool shadowtex1Nearest = true;
    */

    layout(r32ui) uniform uimage2D histX;
    layout(r32ui) uniform uimage2D histY;

    in vec2 texcoord;

    /* RENDERTARGETS:8,7 */
    layout(location = 0) out vec4 color;
    layout(location = 1) out vec4 color1;

    const float sunPathRotation = -40.0;

    const int shadowMapResolution = 2048;
    const float shadowDistance = 192.0;

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

    vec3 sampleShadow(vec3 worldPos, vec3 n, float NdotL){
        vec4 clip = toShadowClip(worldPos);

        vec2 slope;
        rtwsmWarp(clip.xy,slope);
        vec2 texelWorld=vec2(abs(2./shadowProjection[0][0]),abs(2./shadowProjection[1][1]))/(float(shadowMapResolution)*slope);
        float texel=max(texelWorld.x, texelWorld.y);

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
        for(int i=0;i<12;i++){
            float a=float(i)*2.3999632+bn.x;
            vec2 p=sqrt((float(i)+.5)/12.)*vec2(cos(a),sin(a));
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
                    vec3 tint=toAP1(pow(texture(shadowcolor0,suv).rgb,vec3(2.2)));

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

    vec3 cos(vec3 col,vec3 worldPos){
        #ifdef VOLUMETRIC_CLOUDS
            if(cameraPosition.y>CLOUD_ALTITUDE){
                float dist=length(worldPos);
                vec4 cl=raymarch(worldPos/dist,CLOUD_RAY_STEPS,dist);
                col=col*(1.-cl.a)+cl.rgb;
            }
        #endif
        return col;
    }

    vec4 cfetch(ivec2 q,bool readA){
        return readA?texelFetch(samplerCloudA,q,0):texelFetch(samplerCloudB,q,0);
    }

    void cstore(ivec2 px,vec4 v){
        if((frameCounter&1)==0){
            imageStore(cloudHistB,px,v);
        }else{
            imageStore(cloudHistA,px,v);
        }
    }

    vec4 csample(vec2 uv,bool readA,out float cover){
        vec2 pos=uv*RRES-.5;
        ivec2 i0=ivec2(floor(pos));
        vec2 f=pos-vec2(i0);
        ivec2 hi=ivec2(RRES)-1;
        vec4 acc=vec4(0.);
        float ws=0.;
        for(int y=0;y<2;y++){
            for(int x=0;x<2;x++){
                float w=(x==0?1.-f.x:f.x)*(y==0?1.-f.y:f.y);
                ivec2 q=i0+ivec2(x,y);
                if(any(lessThan(q,ivec2(0)))||any(greaterThan(q,hi))) continue;
                vec4 h=cfetch(q,readA);
                if(h.a>.5&&!any(isnan(h))){
                    acc+=vec4(h.rgb,h.a-1.)*w;
                    ws+=w;
                }
            }
        }
        cover=ws;
        return acc/max(ws,1e-4);
    }

    vec4 cloudTemporal(vec3 rd,ivec2 px){
        vec4 cur=volumetricClouds(rd,CLOUD_RAY_STEPS);
        if(any(isnan(cur))) cur=vec4(0.);
        cur.a=saturate(cur.a);

        float yMid=CLOUD_ALTITUDE+CLOUD_THICKNESS*1.1;
        float D=clamp(abs(yMid-cameraPosition.y)/max(abs(rd.y),.03),300.,60000.);
        vec3 pw=rd*D+(cameraPosition-previousCameraPosition);
        vec4 pc=gbufferPreviousProjection*(gbufferPreviousModelView*vec4(pw,1.));

        float w=0.;
        vec4 res=cur;
        if(pc.w>0.){
            vec2 prevUV=pc.xy/pc.w*.5+.5;
            if(all(greaterThan(prevUV,vec2(0.)))&&all(lessThan(prevUV,vec2(1.)))){
                float cover;
                vec4 h=csample(prevUV,(frameCounter&1)==0,cover);

                float vel=length((prevUV-texcoord)*RRES);
                w=clamp(CLOUD_TEMPORAL_BLEND,0.,.98);
                w*=1.-.7*smoothstep(0.,4.,vel);
                w*=smoothstep(.2,.9,cover);
                float dA=abs(h.a-cur.a);
                float dC=abs(dot(h.rgb-cur.rgb,vec3(.3333)))/(dot(cur.rgb+h.rgb,vec3(.3333))+.05);
                w*=1.-.6*smoothstep(.5,1.,max(dA,dC));
                res=mix(cur,h,w);
            }
        }

        cstore(px,vec4(max(res.rgb,0.),res.a+1.));
        return res;
    }

    void cvali(ivec2 px){
        cstore(px,vec4(0.));
    }

    void main(){
        ivec2 px=ivec2(gl_FragCoord.xy);
        vec4 albedo=texelFetch(colortex0,px,0);
        float depth=texelFetch(depthtex0,px,0).r;
        if(abs(texelFetch(colortex13,px,0).w)>.5) depth=texelFetch(depthtex1,px,0).r;

        color=albedo;
        color1=vec4(0.,0.,0.,1.);
        if(depth>=1.){
            #ifdef VOLUMETRIC_CLOUDS
                vec3 skyRd=normalize(worldSpacePosition(texcoord,1.));
                vec4 cl=cloudTemporal(skyRd,px);
                color=vec4(albedo.rgb*(1.-cl.a)+cl.rgb,albedo.a);
            #endif
            return;
        }
        cvali(px);

        vec3 worldPos=worldSpacePosition(texcoord,depth);

        vec3 gc=cross(dFdx(worldPos),dFdy(worldPos));
        vec3 ng=gc/max(length(gc),1e-8);
        if(dot(ng,worldPos)>0.) ng=-ng;

        vec3 L=lightDirection();
        float NdotLg=clamp(dot(ng,L),0.,1.);

        vec4 shadowClip=toShadowClip(worldPos);
        vec2 suv=shadowClip.xy*.5+.5;
        if(((px.x&3)|(px.y&3))==0 && suv.x>=0.&&suv.x<=1.&&suv.y>=0.&&suv.y<=1.){
            int binX=clamp(int(suv.x*float(256)),0,256-1);
            int binY=clamp(int(suv.y*float(256)),0,256-1);
            imageAtomicAdd(histX,ivec2(binX,0),1u);
            imageAtomicAdd(histY,ivec2(binY,0),1u);
        }

        vec3 visC=sampleShadow(worldPos,ng,NdotLg);

        vec4 nd=texelFetch(colortex3,px,0);
        if(dot(nd.xyz,nd.xyz)<.25){
            color=vec4(cos(albedo.rgb*mix(vec3(.35),vec3(1.),visC),worldPos),albedo.a);
            return;
        }

        vec3 N=normalize(nd.xyz);
        vec4 spec=texelFetch(colortex2,px,0);
        vec2 lm=texelFetch(colortex4,px,0).rg;

        vec3 albedoLin=toAP1(pow(albedo.rgb,vec3(2.2)));
        Material m=decodeLabPBR(spec,albedoLin);
        m.ao=nd.w;

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
        vec3 skyR=skyRadiance(R);
        #ifdef VOLUMETRIC_CLOUDS
            float rflW=1.-smoothstep(.2,.4,m.roughness);
            if(rflW>.001&&R.y>.001&&skyVis>.01){
                vec4 rflCl=volumetricClouds(R,16);
                skyR=mix(skyR,skyR*(1.-rflCl.a)+rflCl.rgb,rflW);
            }
        #endif
        vec3 skyEnv=mix(skyR,skyDiff,m.roughness)*skyVis;
        skyEnv*=mix(.15,1.,smoothstep(-.1,.05,R.y));
        vec3 ambient=evalAmbient(m,N,V,skyDiff,skyEnv);

        vec3 sa=specalbedo(m,max(dot(N,V),1e-3));
        float specW=idrspecweight(m.roughness);

        float bl=pow(lm.x,4.);
        vec3 blockLight=toAP1(vec3(1.,.52,.22))*24.*bl*m.ao;
        vec3 blockDiff=m.diffuse*blockLight;
        vec3 blockSpec=sa*specW*blockLight;
        vec3 emissive=m.albedo*m.emission*16.;

        color1=vec4(lightCol*(m.diffuse+sa*specW)*m.ao*skyVis*7.,0.);

        vec3 hdr=direct+ambient+blockDiff+blockSpec+emissive;
        color=vec4(cos(hdr,worldPos),albedo.a);
    }

#endif