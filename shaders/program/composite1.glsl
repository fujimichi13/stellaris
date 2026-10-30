
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
    #include "/lib/utility/space.glsl"
    #include "/lib/utility/dithering.glsl"
    #include "/lib/atmosphere/scattering.glsl"
    #include "/lib/voxel/voxel.glsl"
    #include "/lib/lighting/blockLight.glsl"
    #include "/lib/lighting/irradianceCache.glsl"
    
    in vec2 texcoord;

    /* RENDERTARGETS:5 */
    layout(location=0) out vec4 color;
    
    vec3 ptEmitterRadiance(uint qi){
        storeQD q=vxq.quads[qi];
        float area=max(length(cross(q.p0.xyz-q.p1.xyz,q.p2.xyz-q.p1.xyz)),1e-3);
        uint bid=floatBitsToUint(q.p1.w);
        vec3 col;
        if(bid==11u)
            col=vec3(.25,.6,1.);
        else if(bid==12u)
            col=vec3(1.,.12,.05);
        else if(bid==13u)
            col=vec3(1.,.55,.2);
        else{
            vec3 g=pow(max(unpackUnorm4x8(floatBitsToUint(q.p2.w)).rgb,vec3(1e-3)),vec3(2.2));
            g /= max(max(g.r,g.g),max(g.b,1e-3));
            col=clamp(mix(vec3(luminance(g)),g,1.6),0.,1.);
        }
        return col*(20. / area);
    }

    vec3 icEstimate(vec3 hp,vec3 hn,float skyF,vec3 L,vec3 lightCol){
        vec3 ro=hp+hn*.01;
        vec3 acc=getblocklight(ro,hn);

        if(dot(hn,L)>0.){
            vec3 sd=conedir(L,rand2());
            float ndl=dot(hn,sd);
            if(ndl>0.) acc+=(ndl/PI)*lightCol*traceTrans(ro,sd,256.);
        }

        vec3 wi=cosinedir(hn,rand2());
        hit h;
        vec4 alb;
        uint bid;
        float tHit;
        vec3 tint;
        if(!closest(ro,wi,96.,h,alb,bid,tHit,tint)){
            acc+=tint*skyF*skyRadiance(wi)*mix(.05,1.,smoothstep(-.2,.05,wi.y));
        }else if(bid!=20u){
            vec3 hn2=h.normal;
            if(dot(hn2,wi)>0.) hn2=-hn2;
            vec3 hp2=ro+wi*tHit;
            vec3 E2;
            if(icLookup(hp2+hn2*.01,hn2,E2))
                acc+=tint*pow(alb.rgb,vec3(2.2))*E2;
        }
        return acc;
    }

    vec3 radiance(vec3 P,vec3 N,float skyF,vec3 L,vec3 lightCol,vec2 firstNoise){
        vec3 acc=vec3(0.);
        vec3 thr=vec3(1.);
        vec3 ro0=P+N*max(.02,.004*length(P));
        vec3 n=N;

        acc += getblocklight(ro0,N);

        for(int b=0; b<max(PT_BOUNCES,PT_BOUNCES); b++){
            vec3 wi=cosinedir(n,(b==0)?firstNoise:rand2());

            hit h;
            vec4 alb;
            uint bid;
            float tHit;
            vec3 tint;
            bool found=closest(ro0,wi,96.,h,alb,bid,tHit,tint);
            thr *= tint;
            if(!found){
                if(b<PT_BOUNCES)
                    acc += thr*skyF*skyRadiance(wi)*mix(.05,1.,smoothstep(-.2,.05,wi.y));
                break;
            }

            vec3 hn=h.normal;
            if(dot(hn,wi)>0.) hn=-hn;
            vec3 hp=ro0+wi*tHit;
            vec3 a=pow(alb.rgb,vec3(2.2));

            if(bid!=20u){
                vec3 icP=hp+hn*.01;
                vec3 E;
                bool icOk=icLookup(icP,hn,E);

                if(b==0&&(!icOk||rand()*float(4)<1.))
                    icUpdate(icP,hn,icEstimate(hp,hn,skyF,L,lightCol));

                if(icOk){
                    acc += thr*a*E;
                    break;
                }
            }

            if(bid >= 10u&&bid<=13u&&b>PT_BOUNCES)
                acc += thr*ptEmitterRadiance(h.quad);

            if(b<PT_BOUNCES) acc += thr*a*getblocklight(hp+hn*.01,hn);

            if(b<PT_BOUNCES&&dot(hn,L)>0.){
                vec3 sd=conedir(L,rand2());
                float ndl=dot(hn,sd);
                if(ndl>0.) acc += thr*a*(ndl / PI)*lightCol*traceTrans(hp+hn*.01,sd,256.);
            }

            thr *= a;
            n=hn;
            ro0=hp+hn*.01;

            if(b >= 1){
                float pr=clamp(max(thr.r,max(thr.g,thr.b))*4.,.1,1.);
                if(rand()>pr) break;
                thr /= pr;
            }
        }
        return acc;
    }

    void main(){
        color=vec4(0.);

        ivec2 hp=ivec2(gl_FragCoord.xy);
        ivec2 fullRes=ivec2(RRES);

        ivec2 jit=ivec2(frameCounter&1,(frameCounter>>1)&1);
        ivec2 fp=hp*2+jit;
        if(any(greaterThanEqual(fp,fullRes))) return;

        float depth=texelFetch(depthtex0,fp,0).r;
        if(abs(texelFetch(colortex13,fp,0).w)>.5) depth=texelFetch(depthtex1,fp,0).r;
        if(depth>=1.||depth<.56) return;

        uvec4 gbFp=texelFetch(colortex3,fp,0);
        vec4 nd=gbPresent(gbFp)?vec4(gbUnpackNormal(gbFp),float(gbFp.z>>24)*(1./255.)):vec4(0.);
        if(dot(nd.xyz,nd.xyz)<.25) return;

        float skyLm=gbUnpackLM(gbFp).y;
        float skyF=pow(skyLm,SKYLIGHT_CURVE)*pow(.9667,4.-SKYLIGHT_CURVE);

        vec3 N=normalize(nd.xyz);
        vec3 worldPos=worldSpacePosition((vec2(fp)+.5)/RRES,depth);

        vec3 L=lightDirection();
        vec3 lightCol=lightColor(sunDirection());

        state=pcg(uint(fp.x)+pcg(uint(fp.y)+pcg(uint(frameCounter))));
        vec2 bn=bluenoise(vec2(fp)+vec2(37.,91.));

        vec3 sum=vec3(0.);
        for(int s=0;s<PT_SAMPLES;s++){
            vec2 u=(s==0)?bn:rand2();
            sum+=radiance(worldPos,N,skyF,L,lightCol,u);
        }
        sum/=float(PT_SAMPLES);

        color=vec4(sum,length(worldPos));
    }

#endif