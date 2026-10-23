
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

    /*
    const int colortex5Format=RGBA16F;
    const int colortex6Format=R32F;

    const bool colortex5Clear=false;
    const bool colortex6Clear=false;
    */

    in vec2 texcoord;

    /* RENDERTARGETS:5,6 */
    layout(location=0) out vec4 color;
    layout(location=1) out vec4 color1;

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

    vec3 getblocklight(vec3 P,vec3 N){
        ivec3 c0=cellCoord(P);

        int cellIdx[27];
        uint cellCnt[27];
        float cellG[27];
        float cum[27];
        int nc=0;
        float W=0.;

        for(int z=-1; z<=1; z++)
        for(int y=-1; y<=1; y++)
        for(int x=-1; x<=1; x++){
            int cell=lightCell(c0+ivec3(x,y,z));
            if(cell<0) continue;
            uint cnt=min(vxl.cellCount[cell],uint(16));
            if(cnt==0u) continue;
            vec3 cc=(vec3(c0+ivec3(x,y,z)-ivec3(16,8,16))+.5)*8.;
            vec3 dc=cc-P;
            float g=1. / (dot(dc,dc)+24.);
            W += float(cnt)*g;
            cellIdx[nc]=cell;
            cellCnt[nc]=cnt;
            cellG[nc]=g;
            cum[nc]=W;
            nc++;
        }
        if(nc==0) return vec3(0.);

        float sumW=0.;
        float selF=0.;
        vec3 selRgb=vec3(0.);
        vec3 selPos=vec3(0.);

        for(int i=0; i<4; i++){
            float tgt=rand()*W;
            int k=0;
            while(k<nc-1&&cum[k]<tgt) k++;
            uint cnt=cellCnt[k];
            uint slot=min(uint(rand()*float(cnt)),cnt-1u);
            vLight lt=vxl.lights[vxl.cellSlots[cellIdx[k]*16+int(slot)]];

            vec2 uv=rand2();
            vec3 pos=lt.a.xyz+lt.e1.xyz*uv.x+lt.e2.xyz*uv.y;
            vec3 d=pos-P;
            float d2=dot(d,d);
            vec3 wi=d*inversesqrt(max(d2,1e-6));

            float cosS=dot(N,wi);
            if(cosS<=0.) continue;
            float cosL=abs(dot(lt.n.xyz,wi));
            vec3 col=unpackUnorm4x8(floatBitsToUint(lt.a.w)).rgb;

            vec3 rgb=col*(20.*cosS*cosL / (d2+.5) / PI);
            float f=dot(rgb,vec3(.2126,.7152,.0722));
            if(f<=1e-6) continue;

            float w=f*W / cellG[k];
            sumW += w;
            if(rand()*sumW<w){
                selF=f;
                selRgb=rgb;
                selPos=pos;
            }
        }

        if(sumW<=0.) return vec3(0.);

        vec3 d=selPos-P;
        float dl=length(d);
        vec3 T=traceTrans(P,d / dl,max(dl-.1,.01));
        return selRgb*T*(sumW / (float(4)*selF));
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
        color1=vec4(0.);

        ivec2 hp=ivec2(gl_FragCoord.xy);
        ivec2 fullRes=ivec2(RRES);

        ivec2 jit=ivec2(frameCounter&1,(frameCounter>>1)&1);
        ivec2 fp=hp*2+jit;
        if(any(greaterThanEqual(fp,fullRes))) return;

        float depth=texelFetch(depthtex0,fp,0).r;
        if(abs(texelFetch(colortex13,fp,0).w)>.5) depth=texelFetch(depthtex1,fp,0).r;
        if(depth>=1.||depth<.56) return;

        vec4 nd=texelFetch(colortex3,fp,0);
        if(dot(nd.xyz,nd.xyz)<.25) return;

        float skyLm=texelFetch(colortex4,fp,0).g;
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

        color=vec4(sum,1.);
        color1=vec4(length(worldPos),0.,0.,0.);
    }

#endif