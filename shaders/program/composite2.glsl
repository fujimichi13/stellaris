

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
    #include "/lib/water/water.glsl"

    in vec2 texcoord;

    float unHandDepth(float d){
        return (d<.56)?((d*2.-1.)/.125)*.5+.5:d;
    }

    /* RENDERTARGETS:0,7 */
    layout(location=0) out vec4 color;
    layout(location=1) out vec4 color1;

    vec3 ACES(vec3 v){
        v=mat3(.59719,.0760,.0284,.35458,.90834,.13383,.04823,.01566,.83777)*max(v,0.)*.0625;
        v=(v*(v+.0245786)-.000090537)/(v*(.983729*v+.432951)+.238081);
        return clamp(mat3(1.60475,-.10208,-.00327,-.53108,1.10813,-.07276,-.07367,-.00605,1.07602)*v,0.,1.);
    }

    #include "/lib/camera/util.glsl"

    vec3 worldSpacePosition(vec2 uv,float depth){
        vec4 v=gbufferProjectionInverse*vec4(uv*2.-1.,depth*2.-1.,1.);
        return (gbufferModelViewInverse*vec4(v.xyz/v.w,1.)).xyz;
    }

    vec3 halfRay(ivec2 q,ivec2 jit){
        vec2 uv=(vec2(q*2+jit)+.5)/RRES;
        vec4 r=gbufferProjectionInverse*vec4(uv*2.-1.,1.,1.);
        return normalize(mat3(gbufferModelViewInverse)*normalize(r.xyz/r.w));
    }

    vec3 waterExtinction(vec3 tint){
        vec3 tn=tint/max(max(tint.r,max(tint.g,tint.b)),1e-3);
        return vec3(.45,.07,.012)+vec3(.18,.10,.0)*(1.-tn);
    }

    float waterFresnel(float cosI){
        float c=clamp(cosI,0.,1.);
        float sinT2=(1.-c*c)/(1.333*1.333);
        float cosT=sqrt(max(1.-sinT2,0.));
        float rs=(c-1.333*cosT)/(c+1.333*cosT);
        float rp=(1.333*c-cosT)/(1.333*c+cosT);
        return .5*(rs*rs+rp*rp);
    }
    
    float waterCosT(float cosI){
        float s2=(1.-cosI*cosI)/(1.333*1.333);
        return sqrt(max(1.-s2,0.));
    }

    void main(){
        ivec2 px=ivec2(gl_FragCoord.xy);
        vec4 base=texelFetch(colortex8,px,0);
        vec4 wgt=texelFetch(colortex7,px,0);
        vec4 wn=texelFetch(colortex13,px,0);

        color1=vec4(texelFetch(colortex0,px,0).rgb,1.);

        float depth0=texelFetch(depthtex0,px,0).r;

        bool skyPx=wgt.a>.5;
        bool glassPx=wn.w<-.5;
        bool waterPx=wn.w>.5&&depth0<1.&&isEyeInWater==0;
        if(skyPx&&!glassPx&&!waterPx){
            color=base;
            return;
        }

        vec3 gi=vec3(0.);

        float depthSel=(abs(wn.w)>.5)?texelFetch(depthtex1,px,0).r:depth0;
        if(!skyPx&&depthSel>=.56){
            ivec2 hres=ivec2(RRES)>>1;
            ivec2 jit=ivec2(frameCounter&1,(frameCounter>>1)&1);

            float depth=texelFetch(depthtex0,px,0).r;
            if(abs(wn.w)>.5) depth=texelFetch(depthtex1,px,0).r;
            vec3 P0=worldSpacePosition(texcoord,depth);
            float d0=length(P0);
            vec3 n0=gbUnpackNormal(texelFetch(colortex3,px,0));
            n0*=inversesqrt(max(dot(n0,n0),1e-8));

            vec2 pos=(vec2(px)+.5)*.5-.5;
            ivec2 bq=ivec2(floor(pos+.5));
            float tolU=1.25*(d0*4./(gbufferProjection[1][1]*RRES.y))+.002*d0+.01;

            vec3 sum=vec3(0.);
            float wsum=0.;
            vec3 bestCol=vec3(0.);
            float bestScore=1e30;

            for(int y=-1;y<=1;y++){
                for(int x=-1;x<=1;x++){
                    ivec2 q=bq+ivec2(x,y);
                    if(any(lessThan(q,ivec2(0)))||any(greaterThanEqual(q,hres))) continue;

                    vec4 gq=GeoHist(q);
                    if(gq.a<=0.) continue;

                    vec3 gcol=OutputD(q);
                    if(any(isnan(gcol))||any(isinf(gcol))) continue;

                    vec3 nq=gq.rgb*inversesqrt(max(dot(gq.rgb,gq.rgb),1e-8));
                    vec3 vq=halfRay(q,jit)*gq.a;

                    float cn=max(dot(n0,nq),0.);
                    vec3 nm=n0+nq;
                    nm*=inversesqrt(max(dot(nm,nm),1e-8));
                    float pr=abs(dot(nm,vq-P0))/tolU;

                    vec2 dd=vec2(q)-pos;
                    float dd2=dot(dd,dd);

                    float score=pr+(1.-cn)*8.+dd2*.25;
                    if(score<bestScore){
                        bestScore=score;
                        bestCol=gcol;
                    }

                    float w=exp(-dd2*1.43)*pow(cn,24.)*exp(-1.5*pr*pr);
                    sum+=gcol*w;
                    wsum+=w;
                }
            }

            gi=(wsum>1e-4)?sum/wsum:bestCol;
            gi*=wgt.rgb;
        }

        vec3 hdr=base.rgb+gi;

        if(waterPx){
            vec4 tl=texelFetch(colortex14,px,0);
            //vec3 refl=texelFetch(colortex15,px,0).rgb;
            vec3 tint=pow(tl.rgb,vec3(2.2));
            float skyVis=tl.a*tl.a;

            vec3 N=normalize(wn.xyz);
            vec3 Pw=worldSpacePosition(texcoord,depth0);
            float dw=length(Pw);
            vec3 V=-Pw/dw;

            float depth1=texelFetch(depthtex1,px,0).r;
            vec3 P1=(depth1<1.)?worldSpacePosition(texcoord,depth1):Pw-V*40.;
            vec3 T=refract(-V,N,1./1.333);
            vec3 Pf=Pw+T*(max(Pw.y-P1.y,0.)/max(-T.y,.1));
            vec4 cp=gbufferProjection*(gbufferModelView*vec4(Pf,1.));
            vec2 uvR=(cp.w>0.)?cp.xy/cp.w*.5+.5:texcoord;
            float edge=min(min(uvR.x,1.-uvR.x),min(uvR.y,1.-uvR.y));
            uvR=mix(texcoord,uvR,smoothstep(0.,.05,edge));
            if(texture(depthtex0,rUV(uvR)).r<depth0-1e-5&&texture(colortex13,rUV(uvR)).w<.5) uvR=texcoord;

            float d2=texture(depthtex1,rUV(uvR)).r;
            bool noFloor=d2>=1.;
            vec3 Pu=(d2<1.)?worldSpacePosition(uvR,d2):Pw-V*40.;
            float th=noFloor?128.:length(Pu-Pw);
            float hu=noFloor?0.:max(Pw.y-Pu.y,0.);

            vec3 L=normalize(mat3(gbufferModelViewInverse)*shadowLightPosition);
            vec3 S=normalize(mat3(gbufferModelViewInverse)*sunPosition);
            float alt=eyeAlt(cameraPosition.y);
            vec3 sunCol=sunLight(S,alt);
            vec3 moonCol=moonLight(S);
            vec3 lightCol=sunCol+moonCol;
            vec3 sky=skyAmbient();

            float Lc=max(L.y,0.);
            float cosTL=waterCosT(Lc);
            float cosTV=max(-T.y,.05);
            
            vec3 sig=waterExtinction(tint);

            vec3 Tv=exp(-sig*th);
            vec3 Td=exp(-sig*hu/cosTL)*(1.-waterFresnel(Lc));
            vec3 under=noFloor?vec3(0.):(texture(colortex8,rUV(uvR)).rgb+gi)*Td*Tv;

            vec3 sunE=lightCol*Lc*(1.-waterFresnel(Lc))*skyVis;
            vec3 skyE=sky*3.14159*.94*skyVis;
            vec3 kS=sig*(1.+cosTV/cosTL)+.0015;
            vec3 kA=sig*(1.+cosTV/.8)+.0015;
            vec3 scat=(sunE*(1.-exp(-kS*th))/kS+skyE*(1.-exp(-kA*th))/kA)*.0015/3.14159;

            hdr=(under+scat)*(1.-waterFresnel(dot(N,V)));
        }

        if(glassPx&&depth0<1.){
            vec4 tl=texelFetch(colortex14,px,0);
            vec3 tint=pow(tl.rgb,vec3(2.2));
            float alpha=tl.a;

            float code=floor(-wn.w);
            float skyLm=fract(-wn.w)/.99;
            float thick=(code<1.5)?.125:((code<2.5)?1.:((code<3.5)?.5:.3));

            vec3 N=normalize(wn.xyz);
            vec3 Pg=worldSpacePosition(texcoord,unHandDepth(depth0));
            vec3 D=normalize(Pg);

            float depth1=texelFetch(depthtex1,px,0).r;
            vec3 Q0=(depth1<1.)?worldSpacePosition(texcoord,unHandDepth(depth1)):Pg+D*64.;

            vec2 uvR=texcoord;
            vec3 T=refract(D,N,1./1.52);
            float cosT=max(-dot(T,N),.05);
            vec3 inside=T*(thick/cosT);
            vec3 shift=(inside-D*dot(inside,D))*float(1.);

            vec4 cp=gbufferProjection*(gbufferModelView*vec4(Q0+shift,1.));
            if(cp.w>0.){
                vec2 u=cp.xy/cp.w*.5+.5;
                float edge=min(min(u.x,1.-u.x),min(u.y,1.-u.y));
                uvR=mix(texcoord,u,smoothstep(0.,.05,edge));
            }
            if(texture(depthtex1,rUV(uvR)).r<depth0-1e-5) uvR=texcoord;

            vec3 under=texture(colortex8,rUV(uvR)).rgb+gi;

            ivec2 qR=ivec2(rUV(uvR)*vec2(viewWidth,viewHeight));
            vec4 wR=texelFetch(colortex13,qR,0);
            vec3 frontAbs=vec3(0.);
            if(wR.w<-.5){
                float cR=floor(-wR.w);
                float thR=(cR<1.5)?.125:((cR<2.5)?1.:((cR<3.5)?.5:.3));
                frontAbs=-log(clamp(pow(texelFetch(colortex14,qR,0).rgb,vec3(2.2)),.02,1.))*thR*.6;
            }
            vec3 backAbs=max(texelFetch(colortex12,qR,0).rgb-frontAbs-.01,0.);
            under*=exp(-backAbs);

            float NdotV=max(dot(N,-D),.001);
            float c5=1.-NdotV;
            float F=.04+.96*c5*c5*c5*c5*c5;

            vec3 L=normalize(mat3(gbufferModelViewInverse)*shadowLightPosition);
            vec3 S=normalize(mat3(gbufferModelViewInverse)*sunPosition);
            float alt=eyeAlt(cameraPosition.y);
            vec3 sunCol=sunLight(S,alt);
            vec3 moonCol=moonLight(S);
            vec3 lightCol=sunCol+moonCol;
            vec3 sky=skyAmbient();

            vec3 absC=-log(clamp(tint,.02,1.));
            float pathLen=thick/cosT;
            vec3 transmit=exp(-absC*pathLen*.6);

            float outdoors=skyLm*skyLm*skyLm*skyLm;
            vec3 scat=tint*outdoors*(sky*.8+lightCol*abs(dot(N,L))*.32)*.05;

            hdr=under*transmit*(1.-F)+scat;
        }

        color=vec4(hdr,base.a);
    }

#endif