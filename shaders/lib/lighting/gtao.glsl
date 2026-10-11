#ifndef GTAO_GLSL
    #define GTAO_GLSL a

    #define PI 3.14159265
    #define H_PI 1.57079633

    vec3 viewPos(ivec2 px, float depth){
        vec2 uv=(vec2(px)+.5)/vec2(viewWidth,viewHeight);
        vec4 v=gbufferProjectionInverse*vec4(uv*2.-1.,depth*2.-1.,1.);
        return v.xyz/v.w;
    }

    float linearDepth(float depth){
        return -gbufferProjection[3][2]/(depth*2.-1.+gbufferProjection[2][2]);
    }

    bool validDepth(float d){
        return d>.56&&d<1.;
    }

    float bayer4(ivec2 p){
        return (float(int[16](0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5)[(p.y&3)*4+(p.x&3)])+.5)/16.;
    }

    float ign(ivec2 p){
        return fract(52.9829189*fract(dot(vec2(p),vec2(.06711056,.00583715))));
    }

    float fastAcos(float x){
        float a=abs(x);
        float r=sqrt(max(1.-a,0.))*(1.5707288+a*(-.2121144+a*(.0742610+a*-.0187293)));
        return x>=0.?r:PI-r;
    }

    vec3 viewnormal(ivec2 px, vec3 P, float d){
        ivec2 res=ivec2(viewWidth,viewHeight);
        ivec2 l=clamp(px-ivec2(1,0),ivec2(0),res-1);
        ivec2 r=clamp(px+ivec2(1,0),ivec2(0),res-1);
        ivec2 b=clamp(px-ivec2(0,1),ivec2(0),res-1);
        ivec2 t=clamp(px+ivec2(0,1),ivec2(0),res-1);

        float dl=texelFetch(depthtex0,l,0).r;
        float dr=texelFetch(depthtex0,r,0).r;
        float db=texelFetch(depthtex0,b,0).r;
        float dt=texelFetch(depthtex0,t,0).r;

        vec3 Pl=viewPos(l,dl)-P;
        vec3 Pr=viewPos(r,dr)-P;
        vec3 Pb=viewPos(b,db)-P;
        vec3 Pt=viewPos(t,dt)-P;

        vec3 dx=(abs(Pl.z)<abs(Pr.z))?-Pl:Pr;
        vec3 dy=(abs(Pb.z)<abs(Pt.z))?-Pb:Pt;

        vec3 n=normalize(cross(dx,dy));
        if(dot(n,P)>0.) n=-n;
        return n;
    }

    float c(ivec2 px, float depth){
        if(!validDepth(depth)) return 1.;

        ivec2 res=ivec2(viewWidth,viewHeight);
        vec3 P=viewPos(px,depth);
        float viewDist=length(P);
        vec3 V=-P/viewDist;
        vec3 N=viewnormal(px,P,depth);

        const float radius=float(GTAO_SEARCH_RADIUS);
        float pxRadius=radius*gbufferProjection[1][1]*.5*viewHeight/max(-P.z,1e-3);
        pxRadius=min(pxRadius,256.);
        if(pxRadius<1.5) return 1.;

        const float falloffRange=.615*radius;
        const float falloffFrom=radius-falloffRange;
        const float falloffMul=-1./falloffRange;
        const float falloffAdd=falloffFrom/falloffRange+1.;

        float noiseSlice=bayer4(px);
        float noiseStep=ign(px);
        #ifdef TAA_ENABLED
            float tOff=fract(float(frameCounter&63)*.6180339887);
            noiseSlice=fract(noiseSlice+tOff);
            noiseStep=fract(noiseStep+tOff*1.3247179572);
        #endif

        float visibility=0.;

        for(int slice=0;slice<GTAO_SLICE_COUNT;slice++){
            float phi=(float(slice)+noiseSlice)/float(GTAO_SLICE_COUNT)*PI;
            vec2 omega=vec2(cos(phi),sin(phi));

            vec3 dirVS=vec3(omega,0.);
            vec3 axis=normalize(cross(dirVS,V));
            vec3 orthoDir=dirVS-dot(dirVS,V)*V;

            vec3 projN=N-axis*dot(N,axis);
            float projNLen=length(projN);
            if(projNLen<1e-4) continue;

            float sgnN=sign(dot(orthoDir,projN));
            float cosN=clamp(dot(projN,V)/projNLen,0.,1.);
            float n=sgnN*fastAcos(cosN);

            float low0=cos(n+H_PI);
            float low1=cos(n-H_PI);
            float hc0=low0;
            float hc1=low1;

            for(int s=0;s<GTAO_DIRECTION_SAMPLE_COUNT;s++){
                float t=(float(s)+noiseStep)/float(GTAO_DIRECTION_SAMPLE_COUNT);
                t=t*t;
                float off=t*pxRadius+1.3;

                ivec2 o=ivec2(round(omega*off));
                {
                    ivec2 q=px+o;
                    if(all(greaterThanEqual(q,ivec2(0)))&&all(lessThan(q,res))){
                        float dq=texelFetch(depthtex0,q,0).r;
                        if(validDepth(dq)){
                            vec3 delta=viewPos(q,dq)-P;
                            float len=length(delta);
                            float shc=dot(delta,V)/max(len,1e-4);
                            float w=clamp(len*falloffMul+falloffAdd,0.,1.);
                            hc0=max(hc0,mix(low0,shc,w));
                        }
                    }
                }
                {
                    ivec2 q=px-o;
                    if(all(greaterThanEqual(q,ivec2(0)))&&all(lessThan(q,res))){
                        float dq=texelFetch(depthtex0,q,0).r;
                        if(validDepth(dq)){
                            vec3 delta=viewPos(q,dq)-P;
                            float len=length(delta);
                            float shc=dot(delta,V)/max(len,1e-4);
                            float w=clamp(len*falloffMul+falloffAdd,0.,1.);
                            hc1=max(hc1,mix(low1,shc,w));
                        }
                    }
                }
            }

            float h1= fastAcos(clamp(hc0,-1.,1.));
            float h0=-fastAcos(clamp(hc1,-1.,1.));
            h0=n+clamp(h0-n,-H_PI,H_PI);
            h1=n+clamp(h1-n,-H_PI,H_PI);

            float sinN=sin(n);
            float iarc0=(cosN+2.*h0*sinN-cos(2.*h0-n))*.25;
            float iarc1=(cosN+2.*h1*sinN-cos(2.*h1-n))*.25;

            visibility+=projNLen*(iarc0+iarc1);
        }

        return clamp(visibility/float(GTAO_SLICE_COUNT),0.,1.);
    }

    float gfilter(ivec2 px){
        ivec2 res=ivec2(viewWidth,viewHeight);

        float dc=texelFetch(depthtex1,px,0).r;
        float centerAO=texelFetch(colortex4,px,0).b;
        if(!validDepth(dc)) return 1.;

        float zc=linearDepth(dc);
        vec3 nc=texelFetch(colortex3,px,0).xyz;
        nc/=max(length(nc),1e-4);

        float sum=0.;
        float wsum=0.;
        for(int y=-2;y<=1;y++){
            for(int x=-2;x<=1;x++){
                ivec2 q=clamp(px+ivec2(x,y),ivec2(0),res-1);
                float dq=texelFetch(depthtex1,q,0).r;
                if(!validDepth(dq)) continue;

                vec3 nq=texelFetch(colortex3,q,0).xyz;
                nq/=max(length(nq),1e-4);

                float w=exp(-abs(linearDepth(dq)-zc)/(.03*zc+.04));
                w*=pow(max(dot(nc,nq),0.),16.);

                sum+=texelFetch(colortex4,q,0).b*w;
                wsum+=w;
            }
        }
        return (wsum>1e-4)?sum/wsum:centerAO;
    }

    vec3 multibounce(float ao, vec3 albedo){
        vec3 a=2.0404*albedo-.3324;
        vec3 b=-4.7951*albedo+.6417;
        vec3 c=2.7552*albedo+.6903;
        return max(vec3(ao),((ao*a+b)*ao+c)*ao);
    }

    float calcGTAO(ivec2 px, vec3 albedoLin){
        float g=pow(max(gfilter(px),1e-4),float(GTAO_INTENSITY));
        return multibounce(g,vec3(dot(albedoLin,vec3(.3333333)))).x;
    }

#endif
