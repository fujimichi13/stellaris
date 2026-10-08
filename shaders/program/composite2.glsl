

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

    /* RENDERTARGETS:0 */
    layout(location = 0) out vec4 color;

    vec3 ACES(vec3 v){
        v=mat3(.59719,.0760,.0284,.35458,.90834,.13383,.04823,.01566,.83777)*max(v,0.)*.0625;
        v=(v*(v+.0245786)-.000090537)/(v*(.983729*v+.432951)+.238081);
        return clamp(mat3(1.60475,-.10208,-.00327,-.53108,1.10813,-.07276,-.07367,-.00605,1.07602)*v,0.,1.);
    }

    const float K3[3]=float[3](.25,.5,.25);

    vec3 worldSpacePosition(vec2 uv, float depth){
        vec4 v=gbufferProjectionInverse*vec4(uv*2.-1.,depth*2.-1.,1.);
        return (gbufferModelViewInverse*vec4(v.xyz/v.w,1.)).xyz;
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

        if(wgt.a>.5){
            color=base;
            return;
        }

        vec3 gi=vec3(0.);

        #ifdef RSM_ENABLED
            ivec2 fullRes=textureSize(colortex3,0);
            ivec2 hres=fullRes>>1;
            ivec2 hp=px>>1;

            float depth=texelFetch(depthtex0,px,0).r;
            if(wn.w>.5) depth=texelFetch(depthtex1,px,0).r;
            vec4 v=gbufferProjectionInverse*vec4(texcoord*2.-1.,depth*2.-1.,1.);
            float d0=length((gbufferModelViewInverse*vec4(v.xyz/v.w,1.)).xyz);
            vec3 n0=normalize(texelFetch(colortex3,px,0).xyz);

            vec4 h0=texelFetch(colortex5,hp,0);
            int s=(h0.a<6.)?2:1;
            
            vec3 sum=vec3(0.);
            float wsum=0.;

            for(int y=-1;y<=1;y++){
                for(int x=-1;x<=1;x++){
                    ivec2 q=hp+ivec2(x,y)*s;
                    if(any(lessThan(q,ivec2(0)))||any(greaterThanEqual(q,hres))) continue;

                    float dq=texelFetch(colortex6,q,0).r;
                    if(dq<=0.) continue;

                    vec3 gq=texelFetch(colortex5,q,0).rgb;
                    if(any(isnan(gq))) continue;

                    vec3 nq=normalize(texelFetch(colortex3,min(q*2,fullRes-1),0).xyz);

                    float w=K3[x+1]*K3[y+1];
                    w*=pow(max(dot(n0,nq),0.),24.);
                    w*=exp(-abs(dq-d0)/(.04*d0*float(s)+.05));

                    sum+=gq*w;
                    wsum+=w;
                }
            }

            gi=(wsum>1e-4)?sum/wsum:h0.rgb;
            gi*=wgt.rgb;
        #endif

        vec3 hdr=base.rgb+gi;

        float depth0=texelFetch(depthtex0,px,0).r;
        if(wn.w>.5&&depth0<1.&&isEyeInWater==0){
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
            if(texture(depthtex0,uvR).r<depth0-1e-5&&texture(colortex13,uvR).w<.5) uvR=texcoord;

            float d2=texture(depthtex1,uvR).r;
            vec3 Pu=(d2<1.)?worldSpacePosition(uvR,d2):Pw-V*40.;
            float th=length(Pu-Pw);
            float hu=max(Pw.y-Pu.y,0.);

            vec3 L=normalize(mat3(gbufferModelViewInverse)*shadowLightPosition);
            vec3 S=normalize(mat3(gbufferModelViewInverse)*sunPosition);
            float alt=eyeAlt(cameraPosition.y);
            vec3 sunCol=toRGB(sunIrr*lutT(samplerTransmittance,S.y,alt*.01))*smoothstep(-.04,.0,S.y);
            vec3 moonCol=vec3(.20,.30,.55)*.35*(1.-smoothstep(-.12,.02,S.y));
            vec3 lightCol=sunCol+moonCol;
            vec3 sky=texture(samplerSky,vec2(.5,.75)).rgb;

            float Lc=max(L.y,0.);
            float cosTL=waterCosT(Lc);
            float cosTV=max(-T.y,.05);
            
            vec3 sig=waterExtinction(tint);

            vec3 Tv=exp(-sig*th);
            vec3 Td=exp(-sig*hu/cosTL)*(1.-waterFresnel(Lc));
            vec3 under=(texture(colortex8,uvR).rgb+gi)*Td*Tv;

            vec3 sunE=lightCol*Lc*(1.-waterFresnel(Lc))*skyVis;
            vec3 skyE=sky*3.14159*.94*skyVis;
            vec3 kS=sig*(1.+cosTV/cosTL)+.0015;
            vec3 kA=sig*(1.+cosTV/.8)+.0015;
            vec3 scat=(sunE*(1.-exp(-kS*th))/kS+skyE*(1.-exp(-kA*th))/kA)*.0015/3.14159;

            hdr=(under+scat)*(1.-waterFresnel(dot(N,V)));
        }

        //color=vec4(pow(ACES(hdr),vec3(.4545455)),base.a);
        color=vec4(hdr,base.a);
    }

#endif