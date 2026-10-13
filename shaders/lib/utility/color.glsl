#ifndef COLOR_GLSL
    #define COLOR_GLSL a

    vec3 toAP1(vec3 c){
        return c*mat3(
            vec3(.6131324224,.3395380158,.0474166960),
            vec3(.0701243808,.9163940113,.0134515240),
            vec3(.0205876575,.1095745716,.8697854040)
        );
    }

    vec3 fromAP1(vec3 c){
        return c*mat3(
            vec3(1.7048586763,-.6217160219,-.0832993717),
            vec3(-.1300768242,1.1407357748,-.0105598017),
            vec3(-.0239640729,-.1289755083,1.1530140189)
        );
    }

    float luma(vec3 col){
        return dot(col,vec3(.2722287168,.6740817658,.0536895174));
    }

    vec3 toLinear(vec3 col){
        return pow(col,vec3(2.2));
    }

    vec3 toGamma(vec3 col){
        return pow(col,vec3(1./2.2));
    }

    //https://github.com/TheRealMJP/BakingLab/blob/master/BakingLab/ACES.hlsl
    vec3 ACES(vec3 v){
        v=mat3(.59719,.0760,.0284,.35458,.90834,.13383,.04823,.01566,.83777)*max(v,0.)*.0625;
        v=(v*(v+.0245786)-.000090537)/(v*(.983729*v+.432951)+.238081);
        return clamp(mat3(1.60475,-.10208,-.00327,-.53108,1.10813,-.07276,-.07367,-.00605,1.07602)*v,0.,1.);
    }

#endif
