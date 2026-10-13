#ifndef RANDOM_GLSL
    #define RANDOM_GLSL a

    float hash11(float p){
        p=fract(p*.1031);
        p*=p+33.33;
        return fract(p*(p+p));
    }

    float hash12(vec2 p){
        vec3 p3=fract(vec3(p.xyx)*.1031);
        p3+=dot(p3,p3.yzx+33.33);
        return fract((p3.x+p3.y)*p3.z);
    }

    vec2 hash22(vec2 p){
        vec3 p3=fract(vec3(p.xyx)*vec3(.1031,.1030,.0973));
        p3+=dot(p3,p3.yzx+33.33);
        return fract((p3.xx+p3.yz)*p3.zy);
    }

    vec2 vogelDisk(int i,int n,float rot){
        float ang=(float(i)+rot)*2.3999632;
        return sqrt((float(i)+.5)/float(n))*vec2(cos(ang),sin(ang));
    }

#endif
