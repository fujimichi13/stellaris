#ifndef MATH_GLSL
    #define MATH_GLSL a

    #define PI 3.14159265
    #define TAU 6.28318531
    #define H_PI 1.57079633

    #define saturate(x) clamp(x,0.,1.)

    float sq(float x){
        return x*x;
    }

    float pow5(float x){
        float x2=x*x;
        return x2*x2*x;
    }

    float linearstep(float lo,float hi,float x){
        return saturate((x-lo)/(hi-lo));
    }

    float remap(float x,float lo,float hi,float outLo,float outHi){
        return mix(outLo,outHi,linearstep(lo,hi,x));
    }

    vec3 safeNormalize(vec3 v){
        return v*inversesqrt(max(dot(v,v),1e-8));
    }

    float henyeyGreenstein(float cosTheta,float g){
        float g2=g*g;
        return (1.-g2)/(4.*PI*pow(max(1.+g2-2.*g*cosTheta,1e-4),1.5));
    }

    float curve(float x){
        return x*x*(3.-2.*x);
    }
    vec2 curve(vec2 x){
        return  x*x*(3.-2.*x);
    }
    vec3 curve(vec3 x){
        return x*x*(3.-2.*x);
    }

#endif
