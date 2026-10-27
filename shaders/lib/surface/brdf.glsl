#ifndef BRDF_GLSL
    #define BRDF_GLSL

    #include "/lib/utility/math.glsl"
    #include "/lib/utility/gbufferData.glsl"

    #define skyVisibility(l) (pow(l,SKYLIGHT_CURVE)*pow(.9667,4.-SKYLIGHT_CURVE))

    vec3 skyDiffuseDir(vec3 N){
        vec3 d=N+vec3(0.,1.,0.);
        return (dot(d,d)<1e-3)?vec3(0.,1.,0.):normalize(d);
    }

    float skyHemisphere(vec3 N){
        return mix(.05,1.,smoothstep(-1.,0.,N.y));
    }

    vec3 fresnel(Material m,float VoH){
        VoH=max(VoH,1e-4);
        return m.F0+(vec3(m.F90)-m.F0)*pow5(1.-VoH);
    }

    float D_GGX(float NoH,float a){
        float a2=a*a;
        float d=NoH*NoH*(a2-1.)+1.;
        return a2/(PI*d*d);
    }

    float V_Smith(float NoV,float NoL,float a){
        float a2=a*a;
        float gv=NoL*sqrt(NoV*NoV*(1.-a2)+a2);
        float gl=NoV*sqrt(NoL*NoL*(1.-a2)+a2);
        return .5/max(gv+gl,1e-5);
    }

    float diffuseBurley(float NoV,float NoL,float LoH,float r){
        float fd90=mix(0.,.5,r)+2.*LoH*LoH*r;
        float fl=1.+(fd90-1.)*pow5(1.-NoL);
        float fv=1.+(fd90-1.)*pow5(1.-NoV);
        return fl*fv*mix(1.,1./1.51,r)/PI;
    }

    vec2 envBRDF(float r,float NoV){
        vec4 v=r*vec4(-1.,-.0275,-.572,.022)+vec4(1.,.0425,1.04,-.04);
        float a=min(v.x*v.x,exp2(-9.28*NoV))*v.x+v.y;
        return vec2(-1.04,1.04)*a+v.zw;
    }

    vec3 msComp(vec3 F0,vec2 ab){
        return 1.+F0*(1./max(ab.x+ab.y,1e-3)-1.);
    }

    vec3 specalbedo(Material m,float NoV){
        vec2 ab=envBRDF(m.roughness,NoV);
        return (m.F0*ab.x+m.F90*ab.y)*msComp(m.F0,ab);
    }

    float idrspecweight(float roughness){
        return mix(.25,1.,roughness);
    }

    float specocc(float NoV,float ao,float r){
        return saturate(pow(NoV+ao,exp2(-16.*r-1.))-1.+ao);
    }

    vec3 doreflc(vec3 N,vec3 R,float r){
        float a=r*r;
        return normalize(mix(N,R,(1.-a)*(sqrt(1.-a)+a)));
    }

    void evalDirectBRDF(Material m,vec3 N,vec3 V,vec3 L,out vec3 diffuse,out vec3 specular){
        float NoLr=dot(N,L);
        float NoL=saturate(NoLr);
        float NoV=max(dot(N,V),1e-3);
        vec3 H=normalize(V+L);
        float NoH=saturate(dot(N,H));
        float VoH=saturate(dot(V,H));

        float a=m.roughness*m.roughness;
        float aw=saturate(a+.0047*.5);
        float norm=(a/aw)*(a/aw);

        vec3 F=fresnel(m,VoH);
        vec3 comp=msComp(m.F0,envBRDF(m.roughness,NoV));
        specular=D_GGX(NoH,aw)*norm*V_Smith(NoV,NoL,aw)*F*comp*NoL;

        float wrap=saturate((NoLr+.5)/1.5);
        float dl=mix(NoL,wrap*wrap,m.sss);
        diffuse=m.diffuse*(1.-F)*diffuseBurley(NoV,NoL,VoH,m.roughness)*dl;
    }

    vec3 evalAmbient(Material m,vec3 N,vec3 V,vec3 skyDiffuse,vec3 skyEnv){
        float NoV=max(dot(N,V),1e-3);
        vec2 ab=envBRDF(m.roughness,NoV);
        vec3 sa=(m.F0*ab.x+m.F90*ab.y)*msComp(m.F0,ab);
        float so=specocc(NoV,m.ao,m.roughness);
        return m.diffuse*(1.-sa)*skyDiffuse*m.ao+sa*skyEnv*so;
    }

    vec3 sampleGGXVNDF(vec3 V,vec3 N,float alpha,vec2 u){
        vec3 T,B;
        basis(N,T,B);
        vec3 Ve=vec3(dot(V,T),dot(V,B),dot(V,N));
        vec3 Vh=normalize(vec3(alpha*Ve.x,alpha*Ve.y,max(Ve.z,1e-4)));

        float lensq=Vh.x*Vh.x+Vh.y*Vh.y;
        vec3 T1=(lensq>1e-7)?vec3(-Vh.y,Vh.x,0.)*inversesqrt(lensq):vec3(1.,0.,0.);
        vec3 T2=cross(Vh,T1);

        float r=sqrt(u.x);
        float phi=TAU*u.y;
        float t1=r*cos(phi);
        float t2=r*sin(phi);
        float s=.5*(1.+Vh.z);
        t2=(1.-s)*sqrt(max(1.-t1*t1,0.))+s*t2;

        vec3 Nh=t1*T1+t2*T2+sqrt(max(1.-t1*t1-t2*t2,0.))*Vh;
        vec3 Ne=normalize(vec3(alpha*Nh.x,alpha*Nh.y,max(Nh.z,0.)));
        return normalize(T*Ne.x+B*Ne.y+N*Ne.z);
    }

#endif