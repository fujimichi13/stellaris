#ifndef ATMOS_SCATTERING
    #define ATMOS_SCATTERING a

    #include "transmittance.glsl"

    float RayleighPhaseFunction(float c){
        return .0596831037*(1.+c*c);
    }

    float AerosolPhaseFunction(float c){
        float den=1.36+1.2*c;
        return .0509296/(den*sqrt(den));
    }

    vec4 multipleScattering(sampler2D lut,float c,float nh,float d){
        float om=6.2831853*(1.-sqrt(max(d*d-R*R,0.))/d);
        vec4 gs=lutT(lut,1.,0.)/lutT(lut,1.,nh);
        vec4 Lg=.0795774715*om*.0954929659*lutT(lut,c,0.)*gs*max(c,0.);
        vec4 Lm=.02*vec4(.217,.347,.594,1.)/(1.+5.*exp(-17.92*c));
        return Lm+Lg;
    }

    vec4 calcInscattering(vec3 O,vec3 V,vec3 S,sampler2D lut,out vec4 T,out float g){
        T=vec4(1.);
        g=raySphere(O,V,R);

        float b=dot(O,V);
        float d=b*b-dot(O,O)+RA*RA;
        if(d<0.||(b>0.&&dot(O,O)>RA*RA)) return vec4(0.);

        float t0=max(-b-sqrt(d),0.);
        float t1=g>0.?g:-b+sqrt(d);
        float dt=(t1-t0)/32.;

        float mc=dot(-V,S);
        float rp=RayleighPhaseFunction(mc);
        float ap=AerosolPhaseFunction(mc);

        vec4 L=vec4(0.);
        for(int i=0;i<32;i++){
            vec3 x=O+V*(t0+(float(i)+.5)*dt);
            float r=length(x);
            float c=dot(x/r,S);
            float nh=(r-R)*.01;

            vec4 rS,aS,ex;
            coefficients(r-R,rS,aS,ex);

            vec4 Ts=lutT(lut,c,nh);
            vec4 ms=multipleScattering(lut,c,nh,r);
            vec4 s=sunIrr*(rS*(rp*Ts+ms)+aS*(ap*Ts+ms));
            vec4 st=exp(-dt*ex);

            L+=T*(s-s*st)/max(ex,1e-7);
            T*=st;
        }
        return L;
    }

    vec3 toRGB(vec4 L){
        return mat4x3(
            137.672389239975,-8.632904716299537,-1.7181567391931372,
            32.549094028629234,91.29801417199785,-12.005406444382531,
            -38.91428392614275,34.31665471469816,29.89044807197628,
            8.572844237945445,-11.103384660054624,117.47585277566478
        )*L;
    }

#endif