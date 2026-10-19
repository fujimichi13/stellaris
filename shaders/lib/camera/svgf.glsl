

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

ivec2 dnJitter(){
    return ivec2(frameCounter & 1,(frameCounter >> 1) & 1);
}

vec3 viewray(ivec2 hp){
    vec2 uv=(vec2(hp*2+dnJitter())+.5) / RRES;
    vec4 r=gbufferProjectionInverse*vec4(uv*2.-1.,1.,1.);
    return normalize(r.xyz / r.w);
}

#ifdef TEMPORAL_PASS

    void main(){
        ivec2 hp=ivec2(gl_GlobalInvocationID.xy);
        ivec2 fullRes=ivec2(RRES);
        ivec2 hres=fullRes >> 1;
        if(any(greaterThanEqual(hp,hres))) return;

        float dist=texelFetch(colortex6,hp,0).r;
        if(dist<=0.){
            imageStore(CurrentFrame,hp,vec4(0.));
            imageStore(MomCurrent,hp,vec4(0.));
            imageStore(GeoCurrent,hp,vec4(0.));
            return;
        }

        ivec2 jit=dnJitter();
        ivec2 fp=min(hp*2+jit,fullRes-1);

        vec3 N=normalize(texelFetch(colortex3,fp,0).xyz);
        float depth=texelFetch(depthtex0,fp,0).r;
        if(abs(texelFetch(colortex13,fp,0).w)>.5) depth=texelFetch(depthtex1,fp,0).r;
        vec3 worldPos=worldSpacePosition((vec2(fp)+.5) / RRES,depth);

        vec3 cur=texelFetch(colortex5,hp,0).rgb;
        if(any(isnan(cur)) || any(isinf(cur))) cur=vec3(0.);
        float lum=luminance(cur);
        if(lum>64.){
            cur *= 64. / lum;
            lum=64.;
        }

        vec3 rel=worldPos+cameraPosition-previousCameraPosition;
        vec4 pc=gbufferPreviousProjection*(gbufferPreviousModelView*vec4(rel,1.));
        float expected=length(rel);

        vec3 histCol=vec3(0.);
        vec2 histMom=vec2(0.);
        float histLen=0.;
        float wsum=0.;

        if(pc.w>0.){
            vec2 puv=pc.xy / pc.w*.5+.5;
            vec2 pp=puv*(RRES*.5)-.5;
            ivec2 b=ivec2(floor(pp));
            vec2 f=fract(pp);

            for(int i=0; i<4; i++){
                ivec2 o=ivec2(i & 1,i >> 1);
                ivec2 q=b+o;
                if(any(lessThan(q,ivec2(0))) || any(greaterThanEqual(q,hres))) continue;

                vec4 pg=imageLoad(HistGeo,q);
                if(pg.a<=0. || abs(pg.a-expected)>.03*expected+.1) continue;
                if(dot(pg.rgb,N)<.8) continue;
                
                vec4 hc=imageLoad(HistCol,q);
                vec4 hm=imageLoad(HistMom,q);
                if(any(isnan(hc)) || any(isnan(hm))) continue;

                vec2 bw=mix(1.-f,f,vec2(o));
                float w=bw.x*bw.y;
                histCol += hc.rgb*w;
                histLen += hc.a*w;
                histMom += hm.rg*w;
                wsum += w;
            }
        }

        vec3 col;
        vec2 mom;
        float len;
        if(wsum>1e-3){
            histCol /= wsum;
            histMom /= wsum;
            histLen /= wsum;
            len=min(histLen+1.,255.);
            float alpha=max(1. / len,.05);
            col=mix(histCol,cur,alpha);
            mom=mix(histMom,vec2(lum,lum*lum),alpha);
        }else{
            len=1.;
            col=cur;
            mom=vec2(lum,lum*lum);
        }

        float var=max(mom.y-mom.x*mom.x,0.);

        if(len<4.){
            float s1=0.,s2=0.,sw=0.;
            for(int y=-3; y<=3; y++){
                for(int x=-3; x<=3; x++){
                    ivec2 q=hp+ivec2(x,y);
                    if(any(lessThan(q,ivec2(0))) || any(greaterThanEqual(q,hres))) continue;

                    float dq=texelFetch(colortex6,q,0).r;
                    if(dq<=0.) continue;

                    vec3 nq=normalize(texelFetch(colortex3,min(q*2+jit,fullRes-1),0).xyz);
                    float w=pow(max(dot(N,nq),0.),64.)*exp(-abs(dq-dist) / (.04*dist+.05));
                    if(w<1e-4) continue;

                    vec3 cq=texelFetch(colortex5,q,0).rgb;
                    if(any(isnan(cq)) || any(isinf(cq))) continue;
                    float lq=min(luminance(cq),64.);

                    s1 += lq*w;
                    s2 += lq*lq*w;
                    sw += w;
                }
            }
            if(sw>1e-3){
                s1 /= sw;
                s2 /= sw;
                var=max(s2-s1*s1,0.);
            }
        }

        imageStore(CurrentFrame,hp,vec4(col,var));
        imageStore(MomCurrent,hp,vec4(mom,len,0.));
        imageStore(GeoCurrent,hp,vec4(N,dist));
    }

#endif

#ifdef SPATIAL_PASS

    #if iters==0
        #define source CurrentFrame
        #define dst AtrA
    #elif iters==1
        #define source AtrA
        #define dst AtrB
    #elif iters==2
        #define source AtrB
        #define dst AtrA
    #elif iters==3
        #define source AtrA
        #define dst AtrB
    #else
        #define source AtrB
        #define dst AtrA
    #endif

    const float k[3]=float[3](1.,2. / 3.,1. / 6.);

    void main(){
        ivec2 hp=ivec2(gl_GlobalInvocationID.xy);
        ivec2 hres=ivec2(RRES) >> 1;
        if(any(greaterThanEqual(hp,hres))) return;

        vec4 gc=imageLoad(GeoCurrent,hp);
        float dp=gc.a;
        vec4 c0=imageLoad(source,hp);

        if(dp<=0.){
            imageStore(dst,hp,vec4(0.));
            #if iters==0
                imageStore(HistCol,hp,vec4(0.));
                imageStore(HistMom,hp,vec4(0.));
                imageStore(HistGeo,hp,vec4(0.));
            #endif
            return;
        }

        vec3 np=gc.rgb;
        vec3 vp=viewray(hp)*dp;
        int stp=1 << iters;

        float varP=0.;
        float vws=0.;
        for(int y=-1; y<=1; y++){
            for(int x=-1; x<=1; x++){
                ivec2 q=hp+ivec2(x,y);
                if(any(lessThan(q,ivec2(0))) || any(greaterThanEqual(q,hres))) continue;
                if(imageLoad(GeoCurrent,q).a<=0.) continue;
                float k=((x==0)?2.:1.)*((y==0)?2.:1.);
                varP += imageLoad(source,q).a*k;
                vws += k;
            }
        }
        varP /= max(vws,1e-3);

        float lp=luminance(c0.rgb);
        float denomL=4.*sqrt(max(varP,0.))+1e-4;

        vec3 sum=c0.rgb;
        float vsum=c0.a;
        float wsum=1.;

        for(int y=-2; y<=2; y++){
            for(int x=-2; x<=2; x++){
                if(x==0&&y==0) continue;

                ivec2 q=hp+ivec2(x,y)*stp;
                if(any(lessThan(q,ivec2(0))) || any(greaterThanEqual(q,hres))) continue;

                vec4 gq=imageLoad(GeoCurrent,q);
                if(gq.a<=0.) continue;

                vec4 cq=imageLoad(source,q);
                if(any(isnan(cq))) continue;

                float h=k[abs(x)]*k[abs(y)];
                float wn=pow(max(dot(np,gq.rgb),0.),128.);

                vec3 vq=viewray(q)*gq.a;
                float wz=exp(-abs(dot(np,vq-vp)) / (.015*dp+.02));
                
                float wl=exp(-abs(lp-luminance(cq.rgb)) / denomL);

                float w=h*wn*wz*wl;
                sum += cq.rgb*w;
                vsum += cq.a*w*w;
                wsum += w;
            }
        }

        vec4 res=vec4(sum / wsum,vsum / (wsum*wsum));
        imageStore(dst,hp,res);

        #if iters==0
            vec4 mc=imageLoad(MomCurrent,hp);
            imageStore(HistCol,hp,vec4(res.rgb,mc.b));
            imageStore(HistMom,hp,vec4(mc.rg,0.,0.));
            imageStore(HistGeo,hp,gc);
        #endif
    }

#endif