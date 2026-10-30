#ifndef IRRADIANCE_CACHE_GLSL
    #define IRRADIANCE_CACHE_GLSL a

    struct icEntry {
        vec3 e;
        uint meta;
    };

    layout(std430,binding=6) coherent buffer icB {
        icEntry entries[];
    } icb;

    struct icSlot {
        int idx;
        uint key;
    };

    icSlot icFind(vec3 hp,vec3 hn){
        vec3 a=abs(hn);
        int face=(a.x>=a.y&&a.x>=a.z)?(hn.x>0.?0:1):((a.y>=a.z)?(hn.y>0.?2:3):(hn.z>0.?4:5));

        ivec3 c=ivec3(floor((hp+cameraPosition)/2.));
        ivec3 dim=ivec3(64,32,64);
        ivec3 w=((c%dim)+dim)%dim;

        uint h=pcg(uint(c.x)+pcg(uint(c.y)+pcg(uint(c.z)+pcg(uint(face)+3u))));

        icSlot s;
        s.idx=((w.z*32+w.y)*64+w.x)*6+face;
        s.key=(h>>16)|1u;
        return s;
    }

    bool icValid(uint meta,uint key){
        uint age=(uint(frameCounter)-meta)&0xFFFFu;
        return (meta>>16)==key&&age<=uint(900);
    }

    bool icLookup(vec3 hp,vec3 hn,out vec3 E){
        icSlot s=icFind(hp,hn);
        icEntry en=icb.entries[s.idx];
        E=en.e;
        return icValid(en.meta,s.key)&&!any(isnan(E));
    }

    void icUpdate(vec3 hp,vec3 hn,vec3 v){
        if(any(isnan(v))||any(isinf(v))) return;
        float lum=dot(v,vec3(.2126,.7152,.0722));
        if(lum>128.) v*=128./lum;

        icSlot s=icFind(hp,hn);
        icEntry en=icb.entries[s.idx];

        vec3 outE=v;
        if(icValid(en.meta,s.key)&&!any(isnan(en.e))) outE=mix(en.e,v,.05);

        en.e=outE;
        en.meta=(s.key<<16)|(uint(frameCounter)&0xFFFFu);
        icb.entries[s.idx]=en;
    }

#endif