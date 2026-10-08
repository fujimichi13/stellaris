

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

    in vec2 texcoord;

    /* RENDERTARGETS:0 */
    layout(location = 0) out vec4 color;

    #define RAYTRACE_STEPS 64
    #define RAYTRACE_REFINEMENT 6

    vec2 bluenoise(vec2 fragCoord){
        return texelFetch(noisetex,ivec2(fragCoord)&127,0).rg;
    }

    vec3 viewSpacePosition(vec2 uv, float depth){
        vec4 v=gbufferProjectionInverse*vec4(uv*2.-1.,depth*2.-1.,1.);
        return v.xyz/v.w;
    }

    float viewDepth(float d){
        return -gbufferProjection[3][2]/(d*2.-1.+gbufferProjection[2][2]);
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

    #include "/lib/surface/ssr.glsl"
    #include "/lib/atmosphere/scattering.glsl"
    #include "/lib/water/water.glsl"    

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

        if(depth<1.&&dot(nd.xyz,nd.xyz)>=.25&&texelFetch(colortex13,px,0).w<.5){
            vec3 N=normalize(nd.xyz);
            vec4 spec=texelFetch(colortex2,px,0);
            vec2 lm=texelFetch(colortex4,px,0).rg;

            Material m=decodeLabPBR(spec,pow(texelFetch(colortex5,px,0).rgb,vec3(2.2)));
            m.ao=nd.w;

            if(m.roughness<.4){
                vec3 P=viewSpacePosition(texcoord,depth);
                vec3 V=-normalize(mat3(gbufferModelViewInverse)*P);
                vec3 Rm=reflect(-V,N);

                vec2 bn=bluenoise(gl_FragCoord.xy);
                vec2 bn2=bluenoise(gl_FragCoord.xy+vec2(37.,17.));
                float a=m.roughness*m.roughness;
                float ph=bn.x*6.2831853;
                float cz=bn.y*2.-1.;
                vec3 j=vec3(sqrt(1.-cz*cz)*vec2(cos(ph),sin(ph)),cz);
                vec3 Rw=normalize(Rm+j*a*2.);
                if(dot(Rw,N)<.02) Rw=Rm;

                vec3 D=normalize(mat3(gbufferModelView)*Rw);
                vec3 Nv=normalize(mat3(gbufferModelView)*N);
                vec4 hit=screenSpaceReflection(P+Nv*(.02-P.z*.004),D,Rw,bn2.x);
                hit.a*=1.-smoothstep(.4*.5,.4,m.roughness);

                float skyVis=lm.y*lm.y;
                vec3 skyDiff=skyRadiance(normalize(N+vec3(0.,1.,0.)))/**SKY_AMBIENT*/*skyVis;
                vec3 R=dominantReflection(N,Rm,m.roughness);
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
            vec3 D=normalize(mat3(gbufferModelView)*R);
            vec3 Nv=normalize(mat3(gbufferModelView)*N);
            vec4 hit=screenSpaceReflection(P+Nv*(.02-P.z*.004),D,R,bluenoise(gl_FragCoord.xy).x);

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

        color=vec4(hdr,1.);
    }

#endif