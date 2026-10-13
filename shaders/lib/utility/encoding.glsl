#ifndef ENCODING_GLSL
    #define ENCODING_GLSL a

    vec2 octEncode(vec3 n){
        n/=abs(n.x)+abs(n.y)+abs(n.z);
        vec2 e=n.z>=0.?n.xy:(1.-abs(n.yx))*vec2(n.x>=0.?1.:-1.,n.y>=0.?1.:-1.);
        return e*.5+.5;
    }

    vec3 octDecode(vec2 f){
        f=f*2.-1.;
        vec3 n=vec3(f.xy,1.-abs(f.x)-abs(f.y));
        float t=max(-n.z,0.);
        n.xy+=vec2(n.x>=0.?-t:t,n.y>=0.?-t:t);
        return normalize(n);
    }

    float encodeTypeLight(float type,float skyLight){
        return -(floor(type+.5)+skyLight*.99);
    }

    float decodeLight(float w){
        return fract(-w)/.99;
    }

#endif
