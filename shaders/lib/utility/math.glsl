#ifndef MATH_GLSL
    #define MATH_GLSL a

    #define PI 3.14159265
    #define TAU 6.28318531
    #define H_PI 1.57079633

    #define saturate(x) clamp(x,0.,1.)
    #define luminance(c) dot((c),vec3(.2126,.7152,.0722))

    float sq(float x){
        return x*x;
    }
    vec3 sq(vec3 x){
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

    uint state;

    uint pcg(uint v){
        uint s=v*747796405u+2891336289u;
        uint w=((s >> ((s >> 28u)+4u)) ^ s)*277803737u;
        return (w >> 22u) ^ w;
    }

    float rand(){
        state=pcg(state);
        return float(state >> 8u)*(1. / 16777216.);
    }

    vec2 rand2(){
        float a=rand();
        return vec2(a,rand());
    }

    void basis(vec3 n,out vec3 t,out vec3 b){
        t=normalize(abs(n.y)<.999?cross(n,vec3(0.,1.,0.)):cross(n,vec3(1.,0.,0.)));
        b=cross(n,t);
    }

    vec3 cosinedir(vec3 n,vec2 u){
        vec3 t,b;
        basis(n,t,b);
        float phi=2.*PI*u.x;
        float r=sqrt(u.y);
        return normalize(t*(r*cos(phi))+b*(r*sin(phi))+n*sqrt(max(1.-u.y,0.)));
    }

    vec3 conedir(vec3 L,vec2 u){
        vec3 t,b;
        basis(L,t,b);
        float phi=2.*PI*u.x;
        vec2 d=vec2(cos(phi),sin(phi))*sqrt(u.y)*.035;
        return normalize(L+t*d.x+b*d.y);
    }

    float hash21(vec2 p){
        vec3 p3=fract(vec3(p.xyx)*.1031);
        p3+=dot(p3,p3.yzx+33.33);
        return fract((p3.x+p3.y)*p3.z);
    }

#endif