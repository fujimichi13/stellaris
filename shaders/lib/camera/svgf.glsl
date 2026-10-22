

#include "/settings.glsl"
#include "/lib/utility/math.glsl"
#include "/lib/utility/uniforms.glsl"
#include "/lib/utility/space.glsl"

layout(local_size_x=8,local_size_y=8) in;
const vec2 workGroupsRender=vec2(.5,.5);

layout(rgba16f) uniform image2D HistCol;
layout(rgba32f) uniform image2D HistMom;
layout(rgba16f) uniform image2D HistGeo;

layout(rgba16f) uniform image2D CurrentFrame;
layout(rgba32f) uniform image2D MomCurrent;
layout(rgba16f) uniform image2D GeoCurrent;

layout(rgba16f) uniform image2D AtrA;
layout(rgba16f) uniform image2D AtrB;

const float KB3[3]=float[3](.375,.25,.0625);

#if iters==0
    #define SRC CurrentFrame
    #define DST AtrA
#elif iters==1
    #define SRC AtrA
     #define DST AtrB
#elif iters==2
    #define SRC AtrB
    #define DST AtrA
#elif iters==3
    #define SRC AtrA
    #define DST AtrB
#elif iters==4
    #define SRC AtrB
    #define DST AtrA
#elif iters==5
    #define SRC AtrA
    #define DST AtrB
#else
    #define SRC AtrB
    #define DST AtrA
#endif

ivec2 dnJitter(){
    return ivec2(frameCounter & 1,(frameCounter >> 1) & 1);
}

bool inBounds(ivec2 q,ivec2 res){
    return all(greaterThanEqual(q,ivec2(0))) && all(lessThan(q,res));
}

vec3 viewray(ivec2 hp){
    vec2 uv=(vec2(hp*2+dnJitter())+.5) / RRES;
    vec4 r=gbufferProjectionInverse*vec4(uv*2.-1.,1.,1.);
    return normalize(mat3(gbufferModelViewInverse)*normalize(r.xyz / r.w));
}

float texelFootprint(float d){
    return d*4. / (gbufferProjection[1][1]*RRES.y);
}

float planeTol(float d){
    return 1.25*texelFootprint(d)+.002*d+.01;
}

#ifdef TEMPORAL_PASS

    vec3 prevRay(ivec2 q,mat4 prevProjInv,mat3 prevRotInv){
        vec2 uv=(vec2(q*2)+1.) / RRES;
        vec4 r=prevProjInv*vec4(uv*2.-1.,1.,1.);
        return normalize(prevRotInv*normalize(r.xyz / r.w));
    }

    float histValidity(ivec2 q,vec3 N,vec3 rel,float tolT,mat4 prevProjInv,mat3 prevRotInv,out float pdOut){
        pdOut=1e9;
        if(!inBounds(q,ivec2(RRES) >> 1)) return 0.;
        vec4 pg=imageLoad(HistGeo,q);
        if(pg.a<=0.) return 0.;
        float cn=dot(pg.rgb,N);
        if(cn<.85) return 0.;
        vec3 pq=prevRay(q,prevProjInv,prevRotInv)*pg.a;
        pdOut=abs(dot(safeNormalize(N+pg.rgb),pq-rel));
        if(pdOut>tolT) return 0.;
        return smoothstep(.85,.95,cn)*(1.-.5*smoothstep(.5,1.,pdOut / tolT));
    }

    void main(){
        ivec2 hp=ivec2(gl_GlobalInvocationID.xy);
        ivec2 fullRes=ivec2(RRES);
        ivec2 hres=fullRes >> 1;
        if(any(greaterThanEqual(hp,hres))) return;

        float dist=texelFetch(colortex6,hp,0).r;
        if(dist<=0. || isnan(dist) || isinf(dist)){
            imageStore(CurrentFrame,hp,vec4(0.));
            imageStore(MomCurrent,hp,vec4(0.));
            imageStore(GeoCurrent,hp,vec4(0.));
            return;
        }

        ivec2 jit=dnJitter();
        ivec2 fp=min(hp*2+jit,fullRes-1);

        vec3 N=safeNormalize(texelFetch(colortex3,fp,0).xyz);
        vec3 vp=viewray(hp)*dist;
        float tolS=2.*planeTol(dist);

        float s1=0.,s2=0.,sw=0.;
        for(int y=-2; y<=2; y++){
            for(int x=-2; x<=2; x++){
                if(x==0 && y==0) continue;
                ivec2 q=hp+ivec2(x,y);
                if(!inBounds(q,hres)) continue;

                float dq=texelFetch(colortex6,q,0).r;
                if(dq<=0.) continue;

                vec3 nq=safeNormalize(texelFetch(colortex3,min(q*2+jit,fullRes-1),0).xyz);
                float cn=max(dot(N,nq),0.);
                if(cn<.5) continue;

                float pd=abs(dot(safeNormalize(N+nq),viewray(q)*dq-vp));
                float w=pow(cn,16.)*exp(-1.5*sq(pd / tolS));
                if(w<1e-3) continue;

                vec3 cq=texelFetch(colortex5,q,0).rgb;
                if(any(isnan(cq)) || any(isinf(cq))) continue;
                float lq=min(luminance(cq),64.);

                s1 += lq*w;
                s2 += lq*lq*w;
                sw += w;
            }
        }
        bool haveN=sw>2.;
        float nMean=0.,nSigma=0.;
        if(haveN){
            nMean=s1 / sw;
            nSigma=sqrt(max(s2 / sw-nMean*nMean,0.));
        }

        vec3 cur=texelFetch(colortex5,hp,0).rgb;
        if(any(isnan(cur)) || any(isinf(cur))) cur=vec3(0.);
        float lum=luminance(cur);
        if(lum>64.){ cur*=64. / lum; lum=64.; }

        mat4 prevProjInv=inverse(gbufferPreviousProjection);
        mat3 prevRotInv=transpose(mat3(gbufferPreviousModelView));

        vec3 rel=vp+cameraPosition-previousCameraPosition;
        vec4 pc=gbufferPreviousProjection*(gbufferPreviousModelView*vec4(rel,1.));
        float tolT=2.*planeTol(dist);

        vec3 histCol=vec3(0.);
        vec2 histMom=vec2(0.);
        float histLen=0.;
        float wsum=0.;
        float conf=0.;
        float velPx=0.;

        if(pc.w>.001 && all(lessThan(abs(pc.xy / pc.w),vec2(1.5)))){
            vec2 puv=pc.xy / pc.w*.5+.5;
            vec2 curUV=(vec2(fp)+.5) / RRES;
            velPx=length((puv-curUV)*RRES);

            vec2 pp=puv*RRES*.5-(vec2(jit)+.5)*.5;
            ivec2 b=ivec2(floor(pp));
            vec2 f=fract(pp);

            for(int i=0; i<4; i++){
                ivec2 o=ivec2(i & 1,i >> 1);
                ivec2 q=b+o;

                float pd;
                float vw=histValidity(q,N,rel,tolT,prevProjInv,prevRotInv,pd);
                if(vw<=0.) continue;

                vec4 hc=imageLoad(HistCol,q);
                vec4 hm=imageLoad(HistMom,q);
                if(any(isnan(hc)) || any(isnan(hm)) || any(isinf(hc)) || any(isinf(hm))) continue;

                vec2 bw=mix(1.-f,f,vec2(o));
                float w=bw.x*bw.y*vw;
                histCol += hc.rgb*w;
                histLen += hc.a*w;
                histMom += hm.rg*w;
                wsum += w;
            }
            conf=smoothstep(.1,.9,wsum);

            if(wsum<.25){
                ivec2 bn=ivec2(floor(pp+.5));
                float bestPd=1e9;
                bool found=false;
                vec3 bCol=vec3(0.);
                vec2 bMom=vec2(0.);
                float bLen=0.;
                for(int y=-1; y<=1; y++){
                    for(int x=-1; x<=1; x++){
                        ivec2 q=bn+ivec2(x,y);
                        float pd;
                        float vw=histValidity(q,N,rel,tolT*.75,prevProjInv,prevRotInv,pd);
                        if(vw<=0. || pd>=bestPd) continue;

                        vec4 hc=imageLoad(HistCol,q);
                        vec4 hm=imageLoad(HistMom,q);
                        if(any(isnan(hc)) || any(isnan(hm)) || any(isinf(hc)) || any(isinf(hm))) continue;

                        bestPd=pd;
                        found=true;
                        bCol=hc.rgb;
                        bMom=hm.rg;
                        bLen=hc.a;
                    }
                }
                if(found){
                    histCol=bCol;
                    histMom=bMom;
                    histLen=bLen;
                    wsum=1.;
                    conf=.6;
                }
            }
        }

        bool haveH=wsum>.05;
        if(haveH){
            float iw=1. / wsum;
            histCol *= iw;
            histMom *= iw;
            histLen *= iw*conf;
        }

        float hiLim=haveN ? nMean+4.*nSigma+.05 : 64.;
        if(haveH && histLen>=6.){
            float hm1=histMom.x;
            float hs=sqrt(max(histMom.y-hm1*hm1,0.));
            float hiT=hm1+5.*hs+.1*hm1+.05;
            hiLim=haveN ? max(hiLim,hiT) : hiT;
        }
        if(lum>hiLim){ cur*=hiLim / lum; lum=hiLim; }

        vec3 col;
        vec2 mom;
        float len;

        if(haveH){
            if(haveN){
                float hl=luminance(histCol);
                float kk=2.;
                float lo=max(nMean-kk*nSigma-.03*nMean,0.);
                float hi=nMean+kk*nSigma+.03*nMean+.02;
                float z=(hl>hi) ? (hl-hi) : ((hl<lo) ? (lo-hl) : 0.);
                float relz=z / (nSigma+.05*nMean+.02);
                if(hl>1e-5) histCol*=clamp(hl,lo,hi) / hl;
                histLen*=1.-smoothstep(0.,2.,relz)*.85;
            }

            len=min(histLen+1.,(64.*2.));

            float alpha=max(1. / len,(1. / 64.));
            alpha=max(alpha,.1*smoothstep(1.,16.,velPx));
            alpha=saturate(alpha);

            col=mix(histCol,cur,alpha);
            mom=mix(histMom,vec2(lum,lum*lum),max(alpha,.08));
        }else{
            len=1.;
            col=cur;
            mom=vec2(lum,lum*lum);
        }

        float varT=max(mom.y-mom.x*mom.x,0.);
        float varS=haveN ? nSigma*nSigma : varT;
        float varIn=mix(varS,varT,saturate((len-2.) / 6.));
        if(haveN) varIn=max(varIn,.25*varS);

        float cl=luminance(col);
        varIn=max(varIn,sq(.03*cl)+1e-6);
        if(!haveN && len<4.) varIn=max(varIn,sq(.6*cl)+1e-4);
        
        float neff=min(len,2.*64.-1.);
        float varMean=varIn / neff;

        imageStore(CurrentFrame,hp,vec4(col,varMean));
        imageStore(MomCurrent,hp,vec4(mom,len,0.));
        imageStore(GeoCurrent,hp,vec4(N,dist));
    }

#endif

#ifdef SPATIAL_PASS

    void main(){
        ivec2 hp=ivec2(gl_GlobalInvocationID.xy);
        ivec2 hres=ivec2(RRES) >> 1;
        if(any(greaterThanEqual(hp,hres))) return;

        vec4 gc=imageLoad(GeoCurrent,hp);
        float dp=gc.a;

        if(dp<=0.){
            imageStore(DST,hp,vec4(0.));
            #if iters==0
                imageStore(HistCol,hp,vec4(0.));
                imageStore(HistMom,hp,vec4(0.));
                imageStore(HistGeo,hp,vec4(0.));
            #endif
            return;
        }

        vec4 c0=imageLoad(SRC,hp);
        vec3 np=safeNormalize(gc.rgb);
        vec3 vp=viewray(hp)*dp;
        float tol=planeTol(dp);

        float varP=0.;
        float vws=0.;
        for(int y=-1; y<=1; y++){
            for(int x=-1; x<=1; x++){
                ivec2 q=hp+ivec2(x,y);
                if(!inBounds(q,hres)) continue;
                vec4 gq=imageLoad(GeoCurrent,q);
                if(gq.a<=0.) continue;
                vec4 cq=imageLoad(SRC,q);
                if(isnan(cq.a) || isinf(cq.a)) continue;
                float gk=((x==0) ? 2. : 1.)*((y==0) ? 2. : 1.);
                float wn=pow(max(dot(np,safeNormalize(gq.rgb)),0.),8.);
                varP += cq.a*gk*wn;
                vws += gk*wn;
            }
        }
        varP /= max(vws,1e-4);

        float lp=luminance(c0.rgb);
        float sigL=4.*pow(.84,float(iters));
        float denomL=sigL*sqrt(max(varP,0.))+.05*lp+1e-3;

        float w0=KB3[0]*KB3[0];
        vec3 sum=c0.rgb*w0;
        float vsum=c0.a*w0*w0;
        float wsum=w0;

        for(int y=-2; y<=2; y++){
            for(int x=-2; x<=2; x++){
                if(x==0 && y==0) continue;

                ivec2 q=hp+ivec2(x,y)*(1<<iters);
                if(!inBounds(q,hres)) continue;

                vec4 gq=imageLoad(GeoCurrent,q);
                if(gq.a<=0.) continue;

                vec4 cq=imageLoad(SRC,q);
                if(any(isnan(cq)) || any(isinf(cq))) continue;

                vec3 nq=safeNormalize(gq.rgb);
                float cn=max(dot(np,nq),0.);
                if(cn<.3) continue;

                vec3 vq=viewray(q)*gq.a;
                float pd=abs(dot(safeNormalize(np+nq),vq-vp));
                float wg=pow(cn,32.)*exp(-1.5*sq(pd / tol));
                if(wg<1e-4) continue;

                float wl=exp(-abs(lp-luminance(cq.rgb)) / denomL);

                float w=KB3[abs(x)]*KB3[abs(y)]*wg*wl;
                sum += cq.rgb*w;
                vsum += cq.a*w*w;
                wsum += w;
            }
        }

        vec4 res=vec4(sum / wsum,vsum / (wsum*wsum));
        imageStore(DST,hp,res);

        #if iters==0
            vec4 mc=imageLoad(MomCurrent,hp);
            imageStore(HistCol,hp,vec4(res.rgb,mc.b));
            imageStore(HistMom,hp,vec4(mc.rg,0.,0.));
            imageStore(HistGeo,hp,gc);
        #endif
    }

#endif

#ifdef POST_PASS

    void main(){
        ivec2 hp=ivec2(gl_GlobalInvocationID.xy);
        ivec2 hres=ivec2(RRES) >> 1;
        if(any(greaterThanEqual(hp,hres))) return;

        vec4 gc=imageLoad(GeoCurrent,hp);
        float dp=gc.a;
        if(dp<=0.){
            imageStore(DST,hp,vec4(0.));
            return;
        }

        vec4 c0=imageLoad(SRC,hp);
        if(any(isnan(c0)) || any(isinf(c0))) c0=vec4(0.);

        float lp=luminance(c0.rgb);
        float relStd=sqrt(max(c0.a,0.)) / (lp+.02);
        float strength=smoothstep(.02,.25,relStd);
        if(strength<.01){
            imageStore(DST,hp,c0);
            return;
        }

        vec3 np=safeNormalize(gc.rgb);
        vec3 vp=viewray(hp)*dp;
        float tol=planeTol(dp);
        float denomL=4.*.75*sqrt(max(c0.a,0.))+.05*lp+1e-3;

        vec3 sum=c0.rgb;
        float vsum=c0.a;
        float wsum=1.;

        for(int y=-1; y<=1; y++){
            for(int x=-1; x<=1; x++){
                if(x==0 && y==0) continue;

                ivec2 q=hp+ivec2(x,y);
                if(!inBounds(q,hres)) continue;

                vec4 gq=imageLoad(GeoCurrent,q);
                if(gq.a<=0.) continue;

                vec4 cq=imageLoad(SRC,q);
                if(any(isnan(cq)) || any(isinf(cq))) continue;

                vec3 nq=safeNormalize(gq.rgb);
                float cn=max(dot(np,nq),0.);
                if(cn<.3) continue;

                vec3 vq=viewray(q)*gq.a;
                float pd=abs(dot(safeNormalize(np+nq),vq-vp));
                float wg=pow(cn,32.)*exp(-1.5*sq(pd / tol));
                if(wg<1e-4) continue;

                float wl=exp(-abs(lp-luminance(cq.rgb)) / denomL);
                float h=exp(-float(x*x+y*y)*.69);
                
                float w=h*wg*wl;
                sum += cq.rgb*w;
                vsum += cq.a*w*w;
                wsum += w;
            }
        }

        vec4 fil=vec4(sum / wsum,vsum / (wsum*wsum));
        imageStore(DST,hp,mix(c0,fil,strength));
    }

#endif