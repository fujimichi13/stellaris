#ifndef WATER_GLSL
    #define WATER_GLSL a

    vec2 gr(vec2 p){
        return mat2(-.7373689,-.6754903,.6754903,-.7373689)*p;
    }

    vec4 textureBicubic(sampler2D s, vec2 uv){
        vec2 sz=vec2(textureSize(s,0));
        vec2 x=uv*sz-.5;
        vec2 f=fract(x);
        vec2 i=floor(x);
        vec2 w0=(1.-f)*(1.-f)*(1.-f)/6.;
        vec2 w1=(3.*f*f*f-6.*f*f+4.)/6.;
        vec2 w3=f*f*f/6.;
        vec2 w2=1.-w0-w1-w3;
        vec2 g0=w0+w1;
        vec2 g1=w2+w3;
        vec2 h0=(i-.5+w1/g0)/sz;
        vec2 h1=(i+1.5+w3/g1)/sz;
        return g0.y*(g0.x*texture(s,h0)+g1.x*texture(s,vec2(h1.x,h0.y)))+g1.y*(g0.x*texture(s,vec2(h0.x,h1.y))+g1.x*texture(s,h1));
    }

    float wn1(vec2 c, vec2 dir, float t, bool useBicubic){
        vec2 uv=fract(c+dir*t);
        float n=1.-(useBicubic?textureBicubic(noisetex,uv).z:texture(noisetex,uv).z);
        return n*n;
    }

    float wH(vec2 p, bool F){
        float t=WAVE_SPEED*frameTimeCounter;
        vec2 q=WAVE_SCALE*p;

        float lf=texture(noisetex,fract(q*.2+t*.05)).z;
        float h=.4*(.5+.5*clamp(lf*2.-.75,0.,1.));

        vec2 dir=vec2(.70710678);
        float w=0.,weight=1.;

        int octs=F?WAVE_OCTAVES:WAVE_OCTAVES-1;
        for (int i=0;i<octs;i++) {
            float n=wn1(q,dir,t,F&&i<2);
            w+=n*weight;

            q=gr(1.9*q)+dir*(n*.01);
            dir=gr(dir);
            t*=1.3;
            weight*=.5;
        }
        return h*(w/2.77)*WAVE_HEIGHT;
    }

    vec3 wN(vec2 p){
        float eps=.05;
        float h=wH(p,true);
        float hR=wH(p+vec2(eps,0.),true);
        float hF=wH(p+vec2(0.,eps),true);

        vec3 dX=vec3(eps,hR-h,0.);
        vec3 dZ=vec3(0.,hF-h,eps);

        return normalize(cross(dZ,dX));
    }

    vec3 wNP(vec2 p, vec3 V){
        vec2 st=V.xz/max(V.y,.1)*WAVE_PARALLAX_STRENGTH;

        float h=wH(p,false);
        for(int i=0;i<4;i++){
            h=wH(p+st*h,false);
        }
        return wN(p+st*h);
    }

#endif