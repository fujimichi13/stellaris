

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

    in vec2 texcoord;

    /* RENDERTARGETS:8 */
    layout(location=0) out vec4 color;

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

    void main(){
        color=vec4(0.);

        ivec2 px=ivec2(gl_FragCoord.xy);
        float depth=texelFetch(depthtex0,px,0).r;
        if(depth>=1.||depth<.56) return;

        state=pcg(uint(px.x)+pcg(uint(px.y)+pcg(uint(frameCounter)+7u)));

        vec4 nd=texelFetch(colortex3,px,0);
        vec4 wn=texelFetch(colortex13,px,0);

        vec3 P=viewSpacePosition(texcoord,depth);
        vec3 Pw=(gbufferModelViewInverse*vec4(P,1.)).xyz;
        vec3 V=-normalize(mat3(gbufferModelViewInverse)*P);

        vec3 N;
        vec3 Rr;
        float skyLm;

        if(abs(wn.w)<.5&&dot(nd.xyz,nd.xyz)>=.25){
            N=normalize(nd.xyz);
            Material m=decodeLabPBR(texelFetch(colortex2,px,0),vec3(0.));
            if(m.roughness>=.6) return;

            skyLm=texelFetch(colortex4,px,0).g;

            vec3 Rm=reflect(-V,N);
            float alpha=m.roughness*m.roughness;
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

        for(int b=0;b<3;b++){
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

            int ti=min(max(int(h.st.y*8.),0),7)*8+min(max(int(h.st.x*8.),0),7);
            uint tw=vxq.quads[h.quad].tx[(ti>>1)>>2][(ti>>1)&3];
            tw=(tw>>uint(16*(ti&1)))&0xFFFFu;
            vec3 hitCol=pow(vec3(float(tw>>11),float((tw>>5)&63u),float(tw&31u))/vec3(31.,63.,31.),vec3(2.2));
            #ifdef VOXELIZE_PLAYER
                if(hitId==20u) hitCol=pow(playerSkin(h.uv).rgb,vec3(2.2));
            #endif

            vec3 inc=vec3(0.);

            if(dot(hn,L)>0.){
                vec3 sd=conedir(L,rand2());
                float ndl=dot(hn,sd);
                if(ndl>0.) inc+=(ndl/PI)*lightCol*traceTrans(hro,sd,256.)*sunGate;
            }

            if(b<2){
                vec3 sd=cosinedir(hn,rand2());
                if(!traceAny(hro,sd,96.))
                    inc+=skyRadiance(sd)*mix(.05,1.,smoothstep(-.2,.05,sd.y))*skyGate;
            }

            if(b<2) inc+=getblocklight(hro,hn);

            #ifdef VOXELIZE_PLAYER
             if(hitId==20u)
                inc += skyRadiance(normalize(hn+vec3(0.,1.,0.)))*(.5+.5*hn.y)*.35*skyGate;
            #endif

            float F=.04+.96*pow5(1.-max(dot(-rd,hn),0.));

            c+=thr*((1.-F)*hitCol*inc);
            if(hitId >= 10u&&hitId<=13u) c+=thr*hitCol*16.;

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