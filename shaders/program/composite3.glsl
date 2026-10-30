

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
    #include "/lib/utility/dithering.glsl"
    #include "/lib/utility/space.glsl"
    #include "/lib/atmosphere/scattering.glsl"
    #include "/lib/surface/brdf.glsl"
    #include "/lib/voxel/voxel.glsl"
    #include "/lib/lighting/blockLight.glsl"

    in vec2 texcoord;

    /* RENDERTARGETS:8 */
    layout(location=0) out vec4 color;


    void main(){
        color=vec4(0.);

        ivec2 px=ivec2(gl_FragCoord.xy);
        float depth=texelFetch(depthtex0,px,0).r;
        if(depth>=1.||depth<.56) return;

        state=pcg(uint(px.x)+pcg(uint(px.y)+pcg(uint(frameCounter)+7u)));

        uvec4 gbPx=texelFetch(colortex3,px,0);
        vec4 nd=gbPresent(gbPx)?vec4(gbUnpackNormal(gbPx),float(gbPx.z>>24)*(1./255.)):vec4(0.);
        vec4 wn=texelFetch(colortex13,px,0);

        vec3 P=viewSpacePosition(texcoord,depth);
        vec3 Pw=(gbufferModelViewInverse*vec4(P,1.)).xyz;
        vec3 V=-normalize(mat3(gbufferModelViewInverse)*P);

        vec3 N;
        vec3 Rr;
        float skyLm;

        if(abs(wn.w)<.5&&dot(nd.xyz,nd.xyz)>=.25){
            N=normalize(nd.xyz);
            float rough=gbUnpackRoughness(texelFetch(colortex3,px,0));
            if(rough>=.6) return;

            skyLm=gbUnpackLM(texelFetch(colortex3,px,0)).y;

            vec3 Rm=reflect(-V,N);
            float alpha=rough*rough;
            vec3 Hm=sampleGGXVNDF(V,N,alpha,bluenoise(gl_FragCoord.xy));
            Rr=reflect(-V,Hm);
            if(dot(Rr,N)<=.01) Rr=Rm;
        }else if(wn.w>.5&&isEyeInWater==0){
            N=normalize(wn.xyz);
            Rr=reflect(-V,N);
            Rr.y=abs(Rr.y);
            skyLm=texelFetch(colortex14,px,0).a;
        }else if(wn.w<-.5){
            N=normalize(wn.xyz);
            Rr=reflect(-V,N);
            skyLm=fract(-wn.w)/.99;
        }else{
            return;
        }

        float skyGate=skyVisibility(saturate(skyLm));
        float sunGate=smoothstep(.02,.35,skyLm);

        vec3 L=lightDirection();
        vec3 lightCol=lightColor(sunDirection());

        vec3 ro=Pw+N*max(.02,.004*length(Pw));
        vec3 rd=Rr;
        vec3 thr=vec3(1.);
        vec3 c=vec3(0.);

        int diffHits=0;
        for(int b=0;b<8;b++){
            bool lastBounce=(b==8-1);

            hit h;
            vec4 hitAlb;
            uint hitId;
            float tHit;
            vec3 tint;
            bool found=closest(ro,rd,96.,h,hitAlb,hitId,tHit,tint);
            thr*=tint;

            if(!found){
                if(b==0) return;
                float horizon=mix(.05,1.,smoothstep(-.2,.05,rd.y));
                c+=thr*skyRadiance(rd)*horizon*skyGate;
                break;
            }

            vec3 hn=h.normal;
            if(dot(hn,rd)>0.) hn=-hn;
            float hoff=.01;
            #ifdef VOXELIZE_PLAYER
                if(hitId==20u) hoff=.03;
            #endif
            vec3 hro=ro+rd*tHit+hn*hoff;

            vec3 hitCol=pow(quadTexelRGB(quadTexel(vxq.quads[h.quad],h.st)),vec3(2.2));
            #ifdef VOXELIZE_PLAYER
                if(hitId==20u) hitCol=pow(playerSkin(h.uv).rgb,vec3(2.2));
            #endif

            vec3 F0h=vec3(.04);
            float mir=0.;
            bool metal=false;
            uint sp=floatBitsToUint(vxq.quads[h.quad].p3.w);
            if(hitId!=20u&&((sp>>30)&1u)!=0u){
                float sm=float(sp&255u)/255.;
                uint g=(sp>>8)&255u;
                metal=(g>=230u);
                F0h=metal?clamp(hitCol,0.,1.):vec3(float(g)/255.);
                mir=smoothstep(.55,.9,sm);
            }
            if(lastBounce) mir=0.;

            float fr5=pow5(1.-max(dot(-rd,hn),0.));
            vec3 F=mix(vec3(.04+.96*fr5),F0h+(1.-F0h)*fr5,mir);

            bool needDiffuse=!(metal&&mir>.99);
            vec3 kd=1.-F;
            if(metal) kd*=1.-mir;

            vec3 inc=vec3(0.);
            if(needDiffuse){
                if(dot(hn,L)>0.){
                    vec3 sd=conedir(L,rand2());
                    float ndl=dot(hn,sd);
                    if(ndl>0.) inc+=(ndl/PI)*lightCol*traceTrans(hro,sd,256.)*sunGate;
                }

                if(diffHits<2){
                    vec3 sd=cosinedir(hn,rand2());
                    if(!traceAny(hro,sd,96.))
                        inc+=skyRadiance(sd)*mix(.05,1.,smoothstep(-.2,.05,sd.y))*skyGate;
                    inc+=getblocklight(hro,hn);
                }
                diffHits++;

                #ifdef VOXELIZE_PLAYER
                 if(hitId==20u)
                    inc += skyRadiance(normalize(hn+vec3(0.,1.,0.)))*(.5+.5*hn.y)*.35*skyGate;
                #endif
            }

            c+=thr*(kd*hitCol*inc);
            if(hitId >= 10u&&hitId<=13u){
                float gl=smoothstep(.2,.45,luminance(pow(hitCol,vec3(1./2.2))));
                c+=thr*hitCol*16.*gl;
            }

            thr*=F;
            rd=reflect(rd,hn);
            ro=hro;
            if(max(thr.r,max(thr.g,thr.b))<.03) break;
        }

        if(any(isnan(c))||any(isinf(c))) return;

        float lum=dot(c,vec3(.2126,.7152,.0722));
        if(lum>64.) c*=64./lum;

        color=vec4(c,1.);
    }

#endif