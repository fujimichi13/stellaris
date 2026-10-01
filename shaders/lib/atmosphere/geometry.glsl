#ifndef ATMOS_GEOMETRY
    #define ATMOS_GEOMETRY a

    #include "constants.glsl"

    float raySphere(vec3 ro,vec3 rd,float r){
        float b=dot(ro,rd);
        float c=dot(ro,ro)-r*r;
        if(c>0.&&b>0.) return -1.;
        float d=b*b-c;
        if(d<0.) return -1.;
        if(d>b*b) return -b+sqrt(d);
        return -b-sqrt(d);
    }

    float eyeAlt(float y){
        return max(y,1.)*.001+max(y-256.,0.)*.02;
    }

#endif