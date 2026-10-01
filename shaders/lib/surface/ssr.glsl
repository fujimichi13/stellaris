#ifndef SSR_GLSL
    #define SSR_GLSL a

    vec4 screenSpaceReflection(vec3 P,vec3 D,vec3 Dw,float jit){
        vec2 res=vec2(textureSize(depthtex0,0));

        float len=128.;
        if(D.z>0.) len=min(len,(-.05-P.z)/D.z);
        vec3 P1=P+D*len;

        vec4 h0=gbufferProjection*vec4(P,1.);
        vec4 h1=gbufferProjection*vec4(P1,1.);
        float k0=1./h0.w;
        float k1=1./h1.w;
        float z0=P.z*k0;
        float z1=P1.z*k1;
        vec2 s0=(h0.xy*k0*.5+.5)*res;
        vec2 s1=(h1.xy*k1*.5+.5)*res;

        vec2 d=s1-s0;
        if(abs(d.x)<1e-4) d.x=1e-4;
        if(abs(d.y)<1e-4) d.y=1e-4;
        float dm=max(abs(d.x),abs(d.y));

        vec2 tb=(mix(vec2(0.),res,step(0.,d))-s0)/d;
        float tEnd=min(1.,min(tb.x,tb.y));

        float dt=max(2.,dm*tEnd/float(RAYTRACE_STEPS))/dm;
        float t=dt*(.25+.75*jit);
        float tPrev=0.;

        for(int i=0;i<RAYTRACE_STEPS;i++){
            if(t>tEnd) break;

            vec2 sp=min(s0+d*t,res-1.);
            float rz=mix(z0,z1,t)/mix(k0,k1,t);
            float sz=viewDepth(texelFetch(depthtex0,ivec2(sp),0).r);

            float diff=sz-rz;
            if(diff>0.&&diff<.25-sz*.02){
                float lo=tPrev;
                float hi=t;
                for(int j=0;j<RAYTRACE_REFINEMENT;j++){
                    float m=(lo+hi)*.5;
                    vec2 mp=min(s0+d*m,res-1.);
                    float mz=mix(z0,z1,m)/mix(k0,k1,m);
                    float ms=viewDepth(texelFetch(depthtex0,ivec2(mp),0).r);
                    if(ms-mz>0.) hi=m; else lo=m;
                }

                ivec2 hpx=ivec2(min(s0+d*hi,res-1.));
                vec4 hn=texelFetch(colortex3,hpx,0);

                bool back=dot(hn.xyz,hn.xyz)>.25&&dot(hn.xyz,Dw)>.05;
                if(!back){
                    vec2 uv=(vec2(hpx)+.5)/res;
                    vec2 e=min(uv,1.-uv);
                    float edge=smoothstep(0.,.1,min(e.x,e.y));
                    vec3 c=min(texture(colortex0,uv).rgb,vec3(64.));
                    return vec4(c,edge);
                }
            }

            tPrev=t;
            t+=dt;
        }
        return vec4(0.);
    }

#endif