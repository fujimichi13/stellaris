#ifndef LABPBR_GLSL
    #define LABPBR_GLSL a

    #include "/lib/utility/gbufferData.glsl"
    #include "/lib/utility/color.glsl"

    Material decodeLabPBR(vec4 spec,vec3 albedoLin){
        if(dot(spec,vec4(1.))<1e-4) return materialDefault(albedoLin);

        Material m;
        m.albedo=albedoLin;
        m.smoothness=spec.r;

        int g=int(spec.g*255.+.5);
        if(g<230){
            m.F0=vec3(float(g)/255.);
            m.metallic=0.;
        }else{
            m.F0=albedoLin;
            m.metallic=1.;
        }

        int b=int(spec.b*255.+.5);
        m.porosity=(b<=64)?float(b)/64.:0.;
        m.sss=(b>64)?float(b-65)/190.:0.;

        int a=int(spec.a*255.+.5);
        m.emission=(a<255)?float(a)/254.:0.;

        m.ao=1.;
        m.id=MAT_TERRAIN;
        materialFinalize(m);
        return m;
    }

    vec3 decodeLabPBRNormal(vec4 nt,mat3 tbn,out float ao){
        if(all(lessThan(nt.rgb,vec3(1e-3)))) nt=vec4(.5,.5,1.,1.);
        vec2 xy=nt.rg*2.-1.;
        ao=nt.b;
        return normalize(tbn*vec3(xy,sqrt(max(1.-dot(xy,xy),0.))));
    }

#endif