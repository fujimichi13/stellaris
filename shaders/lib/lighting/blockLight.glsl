#ifndef BLOCKLIGHT_GLSL
    #define BLOCKLIGHT_GLSL a

    vec3 getblocklight(vec3 P,vec3 N){
        ivec3 c0=cellCoord(P);

        int cellIdx[((2*2+1)*(2*2+1)*(2*2+1))];
        float cum[((2*2+1)*(2*2+1)*(2*2+1))];
        int nc=0;
        float W=0.;
        const float R2=(8.*float(2))*(8.*float(2));

        for(int z=-2; z<=2; z++)
        for(int y=-2; y<=2; y++)
        for(int x=-2; x<=2; x++){
            ivec3 cc=c0+ivec3(x,y,z);
            int cell=lightCell(cc);
            if(cell<0) continue;

            vec3 bmin=vec3(cc-ivec3(16,8,16))*8.;
            vec3 q=max(max(bmin-P,P-(bmin+8.)),vec3(0.));
            if(dot(q,q)>=R2) continue;

            uint cnt=vxl.cellCount[cell];
            if(cnt==0u) continue;

            vec3 dc=bmin+4.-P;
            W += float(cnt) / (dot(dc,dc)+24.);
            cellIdx[nc]=cell;
            cum[nc]=W;
            nc++;
        }
        if(nc==0) return vec3(0.);

        float sumW=0.;
        float selF=0.;
        vec3 selRgb=vec3(0.);
        vec3 selPos=vec3(0.);

        for(int i=0; i<8; i++){
            float tgt=rand()*W;
            int k=0;
            while(k<nc-1&&cum[k]<tgt) k++;

            int cell=cellIdx[k];
            uint cnt=vxl.cellCount[cell];
            uint stored=min(cnt,uint(LIGHT_SLOTS));

            vec3 cen=(vec3(ivec3(cell&31,cell >> 10,(cell >> 5)&31)-ivec3(16,8,16))+.5)*8.;
            vec3 dc=cen-P;
            float g=float(cnt) / float(stored) / (dot(dc,dc)+24.);

            uint slot=min(uint(rand()*float(stored)),stored-1u);
            vLight lt=vxl.lights[vxl.cellSlots[cell*LIGHT_SLOTS+int(slot)]];

            vec2 uv=rand2();
            vec3 pos=lt.a.xyz+lt.e1.xyz*uv.x+lt.e2.xyz*uv.y;
            vec3 d=pos-P;
            float d2=dot(d,d);
            vec3 wi=d*inversesqrt(max(d2,1e-6));

            float cosS=dot(N,wi);
            if(cosS<=0.) continue;
            float cosL=abs(dot(lt.n.xyz,wi));
            vec3 col=unpackUnorm4x8(floatBitsToUint(lt.a.w)).rgb;

            float r2=d2 / R2;
            float win=saturate(1.-r2*r2);
            win*=win;

            vec3 rgb=col*(20.*cosS*cosL*win / (d2+.5) / PI);
            float f=dot(rgb,vec3(.2126,.7152,.0722));
            if(f<=1e-6) continue;

            float w=f*W / g;
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
        return selRgb*T*(sumW / (float(8)*selF));
    }

#endif