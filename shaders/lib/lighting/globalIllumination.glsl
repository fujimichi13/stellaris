#ifndef GI_GLSL
    #define GI_GLSL a

    vec3 RSM(vec3 worldPos, vec3 N){
        vec4 clip=toShadowClip(worldPos);
        vec2 clipPerWorld=vec2(abs(shadowProjection[0][0]),abs(shadowProjection[1][1]));
        const float R=6.;
        const int NS=12;

        vec2 bn=fract(bluenoise(gl_FragCoord.xy+vec2(37.,91.))+float(frameCounter&63)*vec2(.7548777,.5698403));
        vec3 sum=vec3(0.);

        for(int i=0;i<NS;i++){
            float a=(float(i)+bn.x)*2.3999632;
            float r=sqrt((float(i)+bn.y)/float(NS));
            vec2 sc=clip.xy+r*vec2(cos(a),sin(a))*R*clipPerWorld;

            vec2 slope;
            vec2 uv=rtwsmWarp(sc,slope)*.5+.5;
            if(uv.x<0.||uv.x>1.||uv.y<0.||uv.y>1.) continue;

            float d1=texture(shadowtex1,uv).r;
            float d0=texture(shadowtex0,uv).r;
            if(d1>=1.||d0<d1-1e-5) continue;

            vec3 xs=(shadowModelViewInverse*(shadowProjectionInverse*vec4(sc,d1*2.-1.,1.))).xyz;
            vec3 ns=normalize(mat3(shadowModelViewInverse)*(texture(shadowcolor1,uv).xyz*2.-1.));
            vec3 flux=pow(texture(shadowcolor0,uv).rgb,vec3(2.2));

            vec3 dv=worldPos-xs;
            float d2=dot(dv,dv)+1.;
            float w=max(dot(ns,dv),0.)*max(dot(N,-dv),0.)/(d2*d2);

            sum+=flux*w;
        }
        return sum*(3.14159265*R*R/float(NS))/3.14159265;
    }

    vec4 rsmTemporal(vec3 worldPos, vec3 cur){
        if(any(isnan(cur))) cur=vec3(0.);

        vec3 rel=worldPos+cameraPosition-previousCameraPosition;
        vec4 pc=gbufferPreviousProjection*(gbufferPreviousModelView*vec4(rel,1.));
        float expected=length(rel);

        vec3 hist=vec3(0.);
        float cnt=0.,wsum=0.;

        if(pc.w>0.){
            vec2 puv=pc.xy/pc.w*.5+.5;
            vec2 res=vec2(textureSize(colortex5,0))*.5;
            vec2 pp=puv*res-.5;
            ivec2 b=ivec2(floor(pp));
            vec2 f=fract(pp);

            for(int i=0;i<4;i++){
                ivec2 o=ivec2(i&1,i>>1);
                ivec2 q=b+o;
                if(any(lessThan(q,ivec2(0)))||any(greaterThanEqual(q,ivec2(res)))) continue;

                float pd=texelFetch(colortex6,q,0).r;
                if(pd<=0.||abs(pd-expected)>.03*expected+.1) continue;

                vec2 bw=mix(1.-f,f,vec2(o));
                float w=bw.x*bw.y;
                vec4 h=texelFetch(colortex5,q,0);
                if(any(isnan(h))) continue;
                hist+=h.rgb*w;
                cnt+=h.a*w;
                wsum+=w;
            }
        }

        if(wsum<1e-3) return vec4(cur,1.);

        hist/=wsum;
        cnt/=wsum;
        float n=min(cnt+1.,32.);
        return vec4(mix(hist,cur,1./n),n);
    }

#endif