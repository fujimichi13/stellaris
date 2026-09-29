#ifndef ATMOS_SCATTERING
    #define ATMOS_SCATTERING a

    #include "transmittance.glsl"

    float RayleighPhaseFunction(float nu){
        return 3./(16.*PI)*(1.+nu*nu);
    }

    float MiePhaseFunction(float g,float nu){
        float k=3./(8.*PI)*(1.-g*g)/(2.+g*g);
        return k*(1.+nu*nu)/pow(1.+g*g-2.*g*nu,1.5);
    }

    void calcLuminanceIntegrand(float r,float mu,float mu_s,float nu,float d,bool intersects_ground,
        sampler2D lut,vec2 lutRes,
        out vec3 rayleigh,
        out vec3 mie
    ){
        float rd=clampRadius(sqrt(max(d*d+2.*r*mu*d+r*r,0.)));
        float mus=clampCosine((r*mu_s+d*nu)/rd);

        vec3 transmittance=getTransmittance(mu,r,d,intersects_ground,lut,lutRes)*getTransmittanceToSun(rd,mus,lut,lutRes);
        rayleigh=transmittance*getProfileDensity(rayleigh_density,rd-A_r);
        mie=transmittance*getProfileDensity(mie_density,rd-A_r);
    }

    void calcSingleScattering(float r,float mu,float mu_s,float d,float nu,bool intersects_ground,
        sampler2D lut,vec2 lutRes,float jitter,
        out vec3 rayleigh,
        out vec3 mie
    ){
        float dx=d/float(SCATTER_SAMPLES);
        vec3 rayleighSum=vec3(0.);
        vec3 mieSum=vec3(0.);

        for(int i=0;i<SCATTER_SAMPLES;i++){
            vec3 rayleighI;
            vec3 mieI;
            calcLuminanceIntegrand(r,mu,mu_s,nu,(float(i)+jitter)*dx,intersects_ground,lut,lutRes,rayleighI,mieI);
            rayleighSum+=rayleighI;
            mieSum+=mieI;
        }

        rayleigh=rayleighSum*dx*ray_s;
        mie=mieSum*dx*mie_s;
    }

#endif