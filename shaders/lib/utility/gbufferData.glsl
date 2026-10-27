#ifndef GBUFFER_DATA_GLSL
    #define GBUFFER_DATA_GLSL a

    #include "/settings.glsl"
    #include "/lib/utility/math.glsl"
    #include "/lib/utility/encoding.glsl"

    struct Material{
        vec3 albedo;
        vec3 diffuse;
        vec3 F0;
        float F90;
        float smoothness;
        float roughness;
        float metallic;
        float ao;
        float emission;
        float sss;
        float porosity;
        uint id;
    };

    float f90From(vec3 F0){
        return saturate(50.*dot(F0,vec3(.33333)));
    }

    float smoothnessToRoughness(float s){
        float p=1.-s;
        return max(p*p,.045);
    }

    void materialFinalize(inout Material m){
        m.F0=saturate(m.F0);
        m.smoothness=saturate(m.smoothness);
        m.metallic=m.metallic>.5?1.:0.;
        m.roughness=smoothnessToRoughness(m.smoothness);
        m.F90=mix(f90From(m.F0),1.,m.metallic);
        m.diffuse=m.albedo*(1.-m.metallic);
    }

    Material materialDefault(vec3 albedoLin){
        Material m;
        m.albedo=albedoLin;
        m.F0=vec3(0.);
        m.smoothness=0.;
        m.metallic=0.;
        m.ao=1.;
        m.emission=0.;
        m.sss=0.;
        m.porosity=.5;
        m.id=MAT_TERRAIN;
        materialFinalize(m);
        return m;
    }

    uint gbPut(float v,uint bits){
        return uint(saturate(v)*float((1u<<bits)-1u)+.5);
    }

    float gbGet(uint word,uint shift,uint bits){
        uint mx=(1u<<bits)-1u;
        return float((word>>shift)&mx)/float(mx);
    }

    uvec4 gbPack(Material m,vec3 N,vec2 lm,float gtao){
        float l=length(N);
        vec3 n=(l>1e-5)?N/l:vec3(0.,1.,0.);

        vec3 f=sqrt(saturate(m.F0));

        uvec4 g;
        g.x=gbPut(f.r,10u)|(gbPut(f.g,10u)<<10)|(gbPut(f.b,10u)<<20)
           |((m.metallic>.5)?(1u<<30):0u)|(1u<<31);
        g.y=packUnorm2x16(octEncode(n));
        g.z=gbPut(lm.x,8u)|(gbPut(lm.y,8u)<<8)|(gbPut(gtao,8u)<<16)|(gbPut(m.ao,8u)<<24);
        g.w=gbPut(m.smoothness,8u)|(gbPut(m.emission,8u)<<8)|(gbPut(m.sss,6u)<<16)
           |(gbPut(m.porosity,6u)<<22)|((m.id&15u)<<28);
        return g;
    }

    bool gbPresent(uvec4 g){
        return (g.x>>31)!=0u;
    }

    Material gbUnpack(uvec4 g,vec3 albedoLin){
        if(!gbPresent(g)) return materialDefault(albedoLin);

        Material m;
        m.albedo=albedoLin;

        vec3 f=vec3(gbGet(g.x,0u,10u),gbGet(g.x,10u,10u),gbGet(g.x,20u,10u));
        m.F0=f*f;
        m.metallic=float((g.x>>30)&1u);

        m.smoothness=gbGet(g.w,0u,8u);
        m.emission=gbGet(g.w,8u,8u);
        m.sss=gbGet(g.w,16u,6u);
        m.porosity=gbGet(g.w,22u,6u);
        m.id=g.w>>28;

        m.ao=float(g.z>>24)*(1./255.);

        materialFinalize(m);
        return m;
    }

    vec3 gbUnpackNormal(uvec4 g){
        return gbPresent(g)?octDecode(unpackUnorm2x16(g.y)):vec3(0.);
    }

    vec2 gbUnpackLM(uvec4 g){
        return gbPresent(g)?vec2(float(g.z&255u),float((g.z>>8)&255u))*(1./255.):vec2(0.);
    }

    float gbUnpackGtao(uvec4 g){
        return float((g.z>>16)&255u)*(1./255.);
    }

    float gbUnpackRoughness(uvec4 g){
        return gbPresent(g)?smoothnessToRoughness(gbGet(g.w,0u,8u)):1.;
    }

    uvec4 gbSetGtao(uvec4 g,float gtao){
        g.z=(g.z&0xFF00FFFFu)|(gbPut(gtao,8u)<<16);
        return g;
    }

#endif