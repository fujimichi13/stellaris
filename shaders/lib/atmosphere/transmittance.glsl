#ifndef ATMOS_TRANSMITTANCE
    #define ATMOS_TRANSMITTANCE a

    #include "geometry.glsl"

    vec4 lutT(sampler2D s,float c,float h){
        return textureLod(s,vec2(clamp(c*.5+.5,0.,1.),clamp(h,0.,1.)),0.);
    }

    void coefficients(float h,out vec4 rS,out vec4 aS,out vec4 ex){
        h=max(h,0.);
        float ad=1.3681e20*exp(-h/.73)+2e6;
        aS=vec4(1.5908e-22,1.7711e-22,2.0942e-22,2.4033e-22)*ad;
        vec4 aA=vec4(2.8722e-24,4.6168e-24,7.9706e-24,1.3578e-23)*ad;
        rS=vec4(6.605e-3,1.067e-2,1.842e-2,3.156e-2)*exp(-.07771971*pow(h,1.16364243));
        float z=log(h+1e-4)-3.22261;
        vec4 oA=vec4(3.472e-21,3.914e-21,1.349e-21,1.103e-22)*.03*3.78547397e20/(h+1e-4)*exp(-z*z*5.55555555);
        ex=aS+aA+rS+oA;
    }

    vec4 calcTransmittance(float c,float r){
        vec3 S=vec3(sqrt(1.-c*c),c,0.);
        vec3 O=vec3(0.,r,0.);
        float dt=raySphere(O,S,RA)/32.;
        vec4 sum=vec4(0.);
        for(int i=0;i<32;i++){
            vec4 rS,aS,ex;
            coefficients(length(O+S*((float(i)+.5)*dt))-R,rS,aS,ex);
            sum+=ex*dt;
        }
        return exp(-sum);
    }

#endif