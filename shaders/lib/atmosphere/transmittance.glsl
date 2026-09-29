#ifndef ATMOS_TRANSMITTANCE
    #define ATMOS_TRANSMITTANCE a

    #include "geometry.glsl"

    float getLayerDensity(const DensityProfileLayer layer,float h){
        return clamp(layer.exp_term*exp(layer.exp_scale*h)+layer.linear_term*h+layer.constant_term,0.,1.);
    }

    float getProfileDensity(const DensityProfile profile,float h){
        return h<profile.layers[0].width?getLayerDensity(profile.layers[0],h):getLayerDensity(profile.layers[1],h);
    }

    float opticalLengthToAtmTop(const DensityProfile profile,float mu,float r){
        float dx=distToExitAtmosphere(mu,r)/float(LUT_SAMPLES);
        float res=0.;
        for(int i=0;i<=LUT_SAMPLES;i++){
            float d=float(i)*dx;
            float ri=sqrt(max(d*d+2.*r*mu*d+r*r,0.));
            float w=(i==0||i==LUT_SAMPLES)?.5:1.;
            res+=getProfileDensity(profile,ri-A_r)*w*dx;
        }
        return res;
    }

    vec3 calcTransmittanceToAtmTop(float mu,float r){
        return exp(-(
            ray_e*opticalLengthToAtmTop(rayleigh_density,mu,r)+
            mie_e*opticalLengthToAtmTop(mie_density,mu,r)+
            ozo_e*opticalLengthToAtmTop(absorption_density,mu,r)
        ));
    }

    vec3 getTransmittanceToAtmTop(float mu,float r,sampler2D lut,vec2 lutRes){
        return texture(lut,muR2uv(mu,r,lutRes)).rgb;
    }

    vec3 getTransmittance(float mu,float r,float d,bool intersects_ground,sampler2D lut,vec2 lutRes){
        float rd=clampRadius(sqrt(max(d*d+2.*r*mu*d+r*r,0.)));
        float mud=clampCosine((r*mu+d)/rd);

        if(intersects_ground){
            return min(getTransmittanceToAtmTop(-mud,rd,lut,lutRes)/getTransmittanceToAtmTop(-mu,r,lut,lutRes),vec3(1.));
        }
        return min(getTransmittanceToAtmTop(mu,r,lut,lutRes)/getTransmittanceToAtmTop(mud,rd,lut,lutRes),vec3(1.));
    }

    vec3 getTransmittanceToSun(float r,float mu_sun,sampler2D lut,vec2 lutRes){
        float sinH=A_r/r;
        float cosH=-sqrt(max(1.-sinH*sinH,0.));
        float visibility=smoothstep(-sinH*.05,sinH*.05,mu_sun-cosH);
        return visibility*getTransmittanceToAtmTop(mu_sun,r,lut,lutRes);
    }

#endif