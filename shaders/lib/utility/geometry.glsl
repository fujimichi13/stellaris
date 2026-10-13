#ifndef GEOMETRY_GLSL
    #define GEOMETRY_GLSL a

    bool shellRoots(float camH,float rdY,float h,float pr,out float t0,out float t1){
        float b=(pr+camH)*rdY;
        float cc=(camH-h)*(2.*pr+camH+h);
        float disc=b*b-cc;
        t0=0.;
        t1=0.;
        if(disc<0.) return false;

        float s=sqrt(disc);
        float q=-(b+(b>=0.?s:-s));
        float tb=(abs(q)>1e-6)?cc/q:q;
        t0=min(q,tb);
        t1=max(q,tb);
        return true;
    }

    bool shellIntersect(float camH,vec3 rd,float hIn,float hOut,float pr,out float tEntry,out float tExit){
        tEntry=0.;
        tExit=0.;
        if(camH<hIn&&rd.y<=0.) return false;

        float o0,o1;
        if(!shellRoots(camH,rd.y,hOut,pr,o0,o1)||o1<0.) return false;

        float entry=max(o0,0.);
        float ext=o1;

        float i0,i1;
        if(shellRoots(camH,rd.y,hIn,pr,i0,i1)&&i1>0.){
            if(camH<hIn) entry=max(entry,i1);
            else if(i0>entry) ext=min(ext,i0);
        }

        tEntry=entry;
        tExit=ext;
        return ext>entry;
    }

    float curvedHeight(vec3 wp,vec2 camXZ,float pr){
        vec2 d=wp.xz-camXZ;
        float d2=dot(d,d);
        float yy=wp.y+pr;
        return (d2+wp.y*wp.y+2.*pr*wp.y)/(sqrt(d2+yy*yy)+pr);
    }

#endif
