

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

    /*
    const int colortex15Format = RGBA16F;
    const bool colortex15Clear = false;
    */

    in vec2 texcoord;

    /* RENDERTARGETS:0,15 */
    layout(location = 0) out vec4 color;
    layout(location = 1) out vec4 color1;

    float luma(vec3 c){
        return dot(c,vec3(.2126,.7152,.0722));
    }
    vec3 compress(vec3 c){
        return c/(1.+luma(c));
    }
    vec3 decompress(vec3 c){
        return c/max(1.-luma(c),1e-6);
    }

    vec3 clipAABB(vec3 c, vec3 e, vec3 h){
        vec3 v=h-c;
        vec3 a=abs(v/max(e,1e-4));
        float m=max(a.x,max(a.y,a.z));
        return (m>1.)?c+v/m:h;
    }

    vec3 sampleHistory(vec2 uv, vec2 size){
        vec2 pos=uv*size;
        vec2 c=floor(pos-.5)+.5;
        vec2 f=pos-c;
        vec2 w0=f*(-.5+f*(1.-.5*f));
        vec2 w1=1.+f*f*(-2.5+1.5*f);
        vec2 w2=f*(.5+f*(2.-1.5*f));
        vec2 w3=f*f*(-.5+.5*f);
        vec2 w12=w1+w2;
        vec2 t0=(c-1.)/size;
        vec2 t3=(c+2.)/size;
        vec2 t12=(c+w2/w12)/size;

        vec3 r=texture(colortex15,vec2(t12.x,t0.y)).rgb*(w12.x*w0.y)
              +texture(colortex15,vec2(t0.x,t12.y)).rgb*(w0.x*w12.y)
              +texture(colortex15,t12).rgb*(w12.x*w12.y)
              +texture(colortex15,vec2(t3.x,t12.y)).rgb*(w3.x*w12.y)
              +texture(colortex15,vec2(t12.x,t3.y)).rgb*(w12.x*w3.y);
        float ws=w12.x*w0.y+w0.x*w12.y+w12.x*w12.y+w3.x*w12.y+w12.x*w3.y;
        return max(r/ws,0.);
    }

    void main(){
        ivec2 px=ivec2(gl_FragCoord.xy);
        vec4 cur=texelFetch(colortex0,px,0);

        if(any(isnan(cur.rgb))) cur.rgb=vec3(0.);

        ivec2 res=ivec2(viewWidth,viewHeight);
        vec2 fres=vec2(res);

        vec3 mean=vec3(0.),m2=vec3(0.),mn=vec3(1e5),mx=vec3(-1e5);
        float closest=2.;
        ivec2 closestOff=ivec2(0);
        for(int y=-1;y<=1;y++){
            for(int x=-1;x<=1;x++){
                ivec2 q=clamp(px+ivec2(x,y),ivec2(0),res-1);
                vec3 s=compress(max(texelFetch(colortex0,q,0).rgb,0.));
                mean+=s; m2+=s*s;
                mn=min(mn,s); mx=max(mx,s);
                float d=texelFetch(depthtex0,q,0).r;
                if(d<closest){ closest=d; closestOff=ivec2(x,y); }
            }
        }
        mean/=9.;
        vec3 sigma=sqrt(max(m2/9.-mean*mean,0.));

        vec2 uvC=(vec2(px+closestOff)+.5)/fres;
        vec2 prevUV;
        bool ok=true;
        if(closest<.56){
            prevUV=texcoord;
        }else{
            vec2 ndc=uvC*2.-1.-taaJitter;
            vec4 v=gbufferProjectionInverse*vec4(ndc,closest*2.-1.,1.);
            vec3 wp=(gbufferModelViewInverse*vec4(v.xyz/v.w,1.)).xyz;
            if(closest<1.) wp+=cameraPosition-previousCameraPosition;
            vec4 pc=gbufferPreviousProjection*(gbufferPreviousModelView*vec4(wp,1.));
            ok=pc.w>0.;
            prevUV=pc.xy/max(pc.w,1e-5)*.5+.5;
            prevUV=texcoord+(prevUV-uvC);
        }
        ok=ok&&all(greaterThan(prevUV,vec2(0.)))&&all(lessThan(prevUV,vec2(1.)));

        float hA=texelFetch(colortex15,clamp(ivec2(prevUV*fres),ivec2(0),res-1),0).a;
        vec3 hRaw=sampleHistory(prevUV,fres);
        if(any(isnan(hRaw))) ok=false;

        vec3 curC=compress(max(cur.rgb,0.));
        vec3 hC=compress(hRaw);

        float aggr=clamp(TAA_AGGRESSION,0.,1.);
        float gamma=mix(2.,.8,aggr);
        vec3 lo=max(mean-gamma*sigma,mn);
        vec3 hi=min(mean+gamma*sigma,mx);
        vec3 hc=clipAABB((lo+hi)*.5,(hi-lo)*.5,hC);

        float vel=length((prevUV-texcoord)*fres);
        float w=TAA_BLENDWEIGHT;
        w*=1.-.6*aggr*smoothstep(0.,4.,vel);
        w*=1.-.75*clamp(length(hC-hc)*2.*aggr,0.,1.);
        if(!ok||hA<.5) w=0.;

        vec3 outC=decompress(mix(curC,hc,w));

        color=vec4(outC,cur.a);
        color1=vec4(outC,1.);
    }

#endif