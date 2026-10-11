#ifndef WATER_FOG_GLSL
    #define WATER_FOG_GLSL a

    vec3 calcWaterFog(vec3 sceneColor, vec3 dir, float dist, float camDepth, vec3 lightDir, vec3 lightCol, vec3 skyCol){
        vec3 sigA=vec3(.45,.07,.012)*WATER_FOG_DENSITY;
        vec3 sigS=vec3(WATER_FOG_SCATTERING);
        vec3 sigT=sigA+sigS;

        float d=(dir.y>1e-3)?min(dist,camDepth/dir.y):dist;

        float Lc=clamp(lightDir.y,0.,1.);
        float cosL=sqrt(1.-(1.-Lc*Lc)/1.7778);
        float Fr=.02+.98*pow(1.-Lc,5.);
        vec3 sunE=lightCol*(1.-Fr)*Lc/cosL;

        float cosT=dot(lightDir,dir);
        float phase=.4375/(12.5663706*pow(1.5625-1.5*cosT,1.5));

        vec3 kS=sigT*(1.-dir.y/cosL);
        vec3 kA=sigT*(1.-dir.y/.83);
        kS=mix(min(kS,vec3(-1e-4)),max(kS,vec3(1e-4)),step(vec3(0.),kS));
        kA=mix(min(kA,vec3(-1e-4)),max(kA,vec3(1e-4)),step(vec3(0.),kA));

        vec3 sunIn=sunE*phase*exp(-sigT*camDepth/cosL)*(1.-exp(-kS*d))/kS;
        vec3 skyIn=skyCol*(.94/(4.*.83))*exp(-sigT*camDepth/.83)*(1.-exp(-kA*d))/kA;

        return sceneColor*exp(-sigT*d)+sigS*(sunIn+skyIn);
    }

#endif
