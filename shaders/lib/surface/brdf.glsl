#ifndef BRDF_GLSL
    #define BRDF_GLSL

    #include "/lib/utility/math.glsl"

    #define skyVisibility(l) (pow(l,SKYLIGHT_CURVE)*pow(.9667,4.-SKYLIGHT_CURVE))

    vec3 skyDiffuseDir(vec3 N){
        vec3 d=N+vec3(0.,1.,0.);
        return (dot(d,d)<1e-3)?vec3(0.,1.,0.):normalize(d);
    }

    float skyHemisphere(vec3 N){
        return mix(.05,1.,smoothstep(-1.,0.,N.y));
    }

    struct Material{
        vec3 albedo;
        vec3 diffuse;
        vec3 F0;
        vec3 eta;
        vec3 kappa;
        bool conductor;
        float roughness;
        float metallic;
        float ao;
        float emission;
        float sss;
        float porosity;
    };

    const vec3 metaleta[8]=vec3[8](
        vec3(2.9114,2.9497,2.5845),
        vec3(.18299,.42108,1.3734),
        vec3(1.3456,.96521,.61722),
        vec3(3.1071,3.1812,2.3230),
        vec3(.27105,.67693,1.3164),
        vec3(1.91,1.83,1.44),
        vec3(2.3757,2.0847,1.8453),
        vec3(.15943,.14512,.13547)
    );
    const vec3 metalk[8]=vec3[8](
        vec3(3.0893,2.9318,2.7670),
        vec3(3.4242,2.3459,1.7704),
        vec3(7.4746,6.3995,5.3031),
        vec3(3.3314,3.3291,3.1350),
        vec3(3.6092,2.6248,2.2921),
        vec3(3.51,3.4,3.18),
        vec3(4.2655,3.7153,3.1365),
        vec3(3.9291,3.19,2.3808)
    );

    vec3 fresnelConductor(float c,vec3 n,vec3 k){
        float c2=c*c;
        vec3 nk=n*n+k*k;
        vec3 rs=(nk-2.*n*c+c2)/(nk+2.*n*c+c2);
        vec3 rp=(nk*c2-2.*n*c+1.)/(nk*c2+2.*n*c+1.);
        return .5*(rs+rp);
    }

    float f90From(vec3 F0){
        return saturate(50.*dot(F0,vec3(.33333)));
    }

    vec3 fresnel(Material m,float VoH){
        VoH=max(VoH,1e-4);
        if(m.conductor) return fresnelConductor(VoH,m.eta,m.kappa);
        return m.F0+(f90From(m.F0)-m.F0)*pow5(1.-VoH);
    }

    Material decodeLabPBR(vec4 spec,vec3 albedo){
        Material m;
        m.albedo=albedo;
        m.roughness=max((1.-spec.r)*(1.-spec.r),.045);

        int g=int(spec.g*255.+.5);
        m.conductor=false;
        m.eta=vec3(0.);
        m.kappa=vec3(0.);
        m.metallic=0.;

        if(g<230){
            m.F0=vec3(float(g)/255.);
        }else if(g<=237){
            m.eta=metaleta[g-230];
            m.kappa=metalk[g-230];
            m.conductor=true;
            m.metallic=1.;
            m.F0=fresnelConductor(1.,m.eta,m.kappa);
        }else{
            m.metallic=1.;
            m.F0=albedo;
        }
        m.diffuse=albedo*(1.-m.metallic);

        int b=int(spec.b*255.+.5);
        m.porosity=(b<=64)?float(b)/64.:0.;
        m.sss=(b>64)?float(b-65)/190.:0.;

        int a=int(spec.a*255.+.5);
        m.emission=(a<255)?float(a)/254.:0.;

        m.ao=1.;
        return m;
    }

    vec3 decodeLabPBRNormal(vec4 nt,mat3 tbn,out float ao){
        if(all(lessThan(nt.rgb,vec3(1e-3)))) nt=vec4(.5,.5,1.,1.);
        vec2 xy=nt.rg*2.-1.;
        ao=nt.b;
        return normalize(tbn*vec3(xy,sqrt(max(1.-dot(xy,xy),0.))));
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
        return (m.F0*ab.x+f90From(m.F0)*ab.y)*msComp(m.F0,ab);
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
        vec3 sa=(m.F0*ab.x+f90From(m.F0)*ab.y)*msComp(m.F0,ab);
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