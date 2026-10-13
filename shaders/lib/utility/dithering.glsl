#ifndef DITHERING_GLSL
    #define DITHERING_GLSL a

    vec2 bluenoiseStatic(vec2 fragCoord){
        return texelFetch(noisetex,ivec2(fragCoord)&127,0).rg;
    }

    vec2 bluenoise(vec2 fragCoord){
        vec2 b=bluenoiseStatic(fragCoord);
        #ifdef TAA_ENABLED
            b=fract(b+float(frameCounter&63)*vec2(.7548777,.5698403));
        #endif
        return b;
    }

    float ign(vec2 p){
        return fract(52.9829189*fract(dot(p,vec2(.06711056,.00583715))));
    }

    float ign(ivec2 p){
        return ign(vec2(p));
    }

    float bayer4(ivec2 p){
        return (float(int[16](0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5)[(p.y&3)*4+(p.x&3)])+.5)/16.;
    }

#endif
