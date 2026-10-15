#ifndef COLOR_GLSL
    #define COLOR_GLSL a

    float luma(vec3 col){
        return dot(col,vec3(.2126,.7152,.0722));
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
