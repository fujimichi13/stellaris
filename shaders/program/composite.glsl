

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
    #include "/lib/atmosphere/scattering.glsl"
    #include "/lib/surface/brdf.glsl"

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

    vec3 worldSpacePosition(vec2 uv, float depth){
        vec4 clip=vec4(uv*2.-1.,depth*2.-1.,1.);
        vec4 viewSpace=gbufferProjectionInverse*clip;
        viewSpace/=viewSpace.w;
        vec4 worldSpace=gbufferModelViewInverse*viewSpace;
        return worldSpace.xyz;
    }

    vec4 toShadowClip(vec3 worldPos){
        vec4 c=shadowProjection*(shadowModelView*vec4(worldPos,1.));
        return vec4(c.xyz/c.w,1.);
    }

    vec2 bluenoise(vec2 fragCoord){
        return texelFetch(noisetex,ivec2(fragCoord)&127,0).rg;
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
        vec2 bn=bluenoise(gl_FragCoord.xy)*6.2831853;

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

    vec3 skyRadiance(vec3 d){
        float t=max(asin(clamp(d.y,-1.,1.)),0.);
        vec3 s=texture(samplerSky,vec2(atan(d.z,d.x)*.15915494+.5,sqrt(t*.63661977)*.5+.5)).rgb;
        return s*(1.-.6*smoothstep(0.,-.4,d.y));
    }

    void main(){
        ivec2 px=ivec2(gl_FragCoord.xy);
        vec4 albedo=texture(colortex0,texcoord);
        float depth=texelFetch(depthtex0,px,0).r;
        if(texelFetch(colortex13,px,0).w>.5) depth=texelFetch(depthtex1,px,0).r;

        color=albedo;
        color1=vec4(0.,0.,0.,1.);
        if(depth>=1.) return;

        vec3 worldPos=worldSpacePosition(texcoord,depth);

        vec3 gc=cross(dFdx(worldPos),dFdy(worldPos));
        vec3 ng=gc/max(length(gc),1e-8);
        if(dot(ng,worldPos)>0.) ng=-ng;

        vec3 L=normalize(mat3(gbufferModelViewInverse)*shadowLightPosition);
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
            color=vec4(albedo.rgb*mix(vec3(.35),vec3(1.),visC),albedo.a);
            return;
        }

        vec3 N=normalize(nd.xyz);
        vec4 spec=texelFetch(colortex2,px,0);
        vec2 lm=texelFetch(colortex4,px,0).rg;

        vec3 albedoLin=pow(albedo.rgb,vec3(2.2));
        Material m=decodeLabPBR(spec,albedoLin);
        m.ao=nd.w;

        vec3 V=-normalize(worldPos);

        vec3 S=normalize(mat3(gbufferModelViewInverse)*sunPosition);
        float alt=eyeAlt(cameraPosition.y);
        vec3 sunCol=toRGB(sunIrr*lutT(samplerTransmittance,S.y,alt*.01))*1.*smoothstep(-.04,.0,S.y);
        vec3 moonCol=vec3(.20,.30,.55)*.35*(1.-smoothstep(-.12,.02,S.y));
        vec3 lightCol=sunCol+moonCol;

        vec3 vis2=visC*smoothstep(0.,.1,NdotLg);
        vis2=mix(vis2,visC*.5,m.sss*step(NdotLg,.001));

        vec3 dDiff,dSpec;
        evalDirectBRDF(m,N,V,L,dDiff,dSpec);
        vec3 direct=(dDiff+dSpec)*lightCol*vis2;

        //float skyVis=lm.y*lm.y;
        float skyVis=pow(lm.y,4.);
        vec3 skyDiff=skyRadiance(normalize(N+vec3(0.,1.,0.)))*1.*skyVis;
        vec3 R=dominantReflection(N,reflect(-V,N),m.roughness);
        vec3 skyEnv=mix(skyRadiance(R),skyDiff,m.roughness)*skyVis;
        skyEnv*=mix(.15,1.,smoothstep(-.1,.05,R.y));
        vec3 ambient=evalAmbient(m,N,V,skyDiff,skyEnv);

        float bl=pow(lm.x,4.);
        vec3 blockDiff=m.diffuse*vec3(1.,.52,.22)*24.*bl*m.ao;
        vec3 emissive=m.albedo*m.emission*16.;

        color1=vec4(lightCol*m.diffuse*m.ao*skyVis*7.,0.);

        vec3 hdr=direct+ambient+blockDiff+emissive;
        color=vec4(hdr,albedo.a);
    }

#endif