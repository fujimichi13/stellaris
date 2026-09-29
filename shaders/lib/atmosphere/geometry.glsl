#ifndef ATMOS_GEOMETRY
    #define ATMOS_GEOMETRY a

    #include "constants.glsl"

    float clampCosine(float mu){
        return clamp(mu,-1.,1.);
    }

    float clampRadius(float r){
        return clamp(r,A_r,A_R);
    }

    float distToExitAtmosphere(float mu,float r){
        float disc=r*r*(mu*mu-1.)+A_R*A_R;
        return max(-r*mu+sqrt(max(disc,0.)),0.);
    }

    float distToEnterPlanet(float mu,float r){
        float disc=r*r*(mu*mu-1.)+A_r*A_r;
        return max(-r*mu-sqrt(max(disc,0.)),0.);
    }

    float unitRange2texCoord(float x,float texSize){
        return .5/texSize+x*(1.-1./texSize);
    }

    float texCoord2unitRange(float u,float texSize){
        return (u-.5/texSize)/(1.-1./texSize);
    }

    vec2 muR2uv(float mu,float r,vec2 texSize){
        float H=sqrt(A_R*A_R-A_r*A_r);
        float rho=sqrt(max(r*r-A_r*A_r,0.));
        float d=distToExitAtmosphere(mu,r);
        float dMin=A_R-r;
        float dMax=rho+H;
        float xMu=(d-dMin)/(dMax-dMin);
        float xR=rho/H;
        return vec2(unitRange2texCoord(xMu,texSize.x),unitRange2texCoord(xR,texSize.y));
    }

    void uv2muR(vec2 uv,out float mu,out float r,vec2 texSize){
        float xMu=texCoord2unitRange(uv.x,texSize.x);
        float xR=texCoord2unitRange(uv.y,texSize.y);
        float H=sqrt(A_R*A_R-A_r*A_r);
        float rho=H*xR;
        r=sqrt(rho*rho+A_r*A_r);
        float dMin=A_R-r;
        float dMax=rho+H;
        float d=dMin+xMu*(dMax-dMin);
        mu=d==0.?1.:(H*H-rho*rho-d*d)/(2.*r*d);
        mu=clamp(mu,-1.,1.);
    }

    bool getIntersectionInfo(vec3 cameraPos,vec3 viewDir,vec3 sunDir,
        out float mu,
        out float mu_s,
        out float r,
        out bool intersects_ground,
        out float d,
        out float nu
    ){
        mu=0.;
        mu_s=0.;
        r=A_r;
        intersects_ground=false;
        d=0.;
        nu=0.;

        vec3 pos=cameraPos+vec3(0.,A_r,0.);
        float tClosest=-dot(viewDir,pos);
        float dClosest=length(pos+viewDir*tClosest);

        if(dClosest>A_R) return false;

        r=length(pos);

        if(r>=A_R&&tClosest>0.){
            float a=sqrt(A_R*A_R-dClosest*dClosest);
            pos+=viewDir*(tClosest-a);
            r=A_R;
        }

        mu=dot(pos,viewDir)/r;
        mu_s=dot(pos,sunDir)/r;
        nu=dot(viewDir,sunDir);

        intersects_ground=dClosest<A_r&&tClosest>0.;
        d=intersects_ground?distToEnterPlanet(mu,r):distToExitAtmosphere(mu,r);
        return d>0.;
    }

#endif