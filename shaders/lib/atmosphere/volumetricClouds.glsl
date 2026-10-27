#ifndef VOLUMETRIC_CLOUDS_GLSL
    #define VOLUMETRIC_CLOUDS_GLSL a

    #include "/lib/utility/math.glsl"
    #include "/lib/utility/geometry.glsl"
    #include "/lib/utility/dithering.glsl"
    #include "/lib/utility/space.glsl"
    #include "/lib/atmosphere/scattering.glsl"

    struct cuweather{
        float thr;
        float tall;
    };

    cuweather cuweatherAt(vec2 xz){
        float S=max(CLOUD_SCALE,.05);
        vec2 mUV=(xz-vec2(1.,.35)*frameTimeCounter*CLOUD_WIND_SPEED)/(S*120000.);

        float macro=textureLod(cuBase,fract(mUV),0.).r*.6+textureLod(cuBase,fract(mUV*2.31+vec2(.37,.71)),0.).r*.4;
        float type=textureLod(cuBase,fract(mUV*.73+vec2(.90,.20)),0.).r;

        float rain=saturate(cloudRain);
        float g=saturate((CLOUD_COVERAGE-.45)/1.1);
        g=mix(g,1.,rain*.7);
        float local=saturate(g+(macro-.35)*1.5);

        cuweather m;
        m.thr=mix(.62,.24,local);
        m.tall=mix(mix(.45,1.,smoothstep(.25,.5,type)),.75,rain);
        return m;
    }

    vec2 cuCell(vec2 xz,cuweather m){
        float S=max(CLOUD_SCALE,.05);
        vec2 p=(xz-vec2(1.,.35)*frameTimeCounter*CLOUD_WIND_SPEED)/S;

        vec2 warp=textureLod(cuCurl,fract(vec3(p/9000.,.17)),0.).xy*.03;
        float c=textureLod(cuBase,fract(p/15000.+warp),0.).r;

        float t=saturate((c-m.thr)/max(.80-m.thr,.1));
        t=pow(t,.6);
        return vec2(saturate(t*m.tall*1.2),t);
    }

    float cuProfile(float h,float top){
        float bottom=smoothstep(0.,.07,h);
        float dome=1.-smoothstep(top*.45,top,h);
        return bottom*dome;
    }

    float cuDensity(vec3 wp,float h,cuweather m,float dist,int quality){
        if(h<=0.||h>=1.) return 0.;

        vec2 cell=cuCell(wp.xz,m);
        if(cell.x<.01) return 0.;

        float S=max(CLOUD_SCALE,.05);
        float th=max(CLOUD_THICKNESS*(1.+.25*saturate(cloudRain)),1.);
        float rain=saturate(cloudRain);
        vec2 wind=vec2(1.,.35)*frameTimeCounter*CLOUD_WIND_SPEED;

        vec3 q=vec3(wp.x-wind.x,h*th+frameTimeCounter*1.5,wp.z-wind.y)/S;

        vec3 cv=vec3(0.);
        if(quality>=1) cv=textureLod(cuCurl,fract(q/1800.),0.).rgb;

        float nb=saturate(textureLod(cuDetail1,fract((q+cv*90.)/1300.),0.).r/.62);
        float nL=saturate(textureLod(cuDetail1,fract((q*.32+vec3(.21,.57,.09)+cv*30.)/1300.),0.).r/.62);

        float top=saturate(cell.x*(.55+.45*nL)*(.7+.6*nb));
        float rel=h/max(top,.02);
        if(rel>=1.) return 0.;

        float baseF=smoothstep(0.,.04+.07*(1.-nb),h);
        float env=baseF*(1.-smoothstep(.5,1.,rel))*(.55+.5*cell.y);
        if(env<.01) return 0.;

        float erosion=2.*(1.-.45*rain)*mix(1.3,.8,cell.y);
        float hEro=mix(.6,1.25,smoothstep(.15,1.,rel));

        float lo=(1.-nb)*.55*erosion*hEro;
        if(quality>=1){
            float n1b=textureLod(cuDetail1,fract((q*2.3+vec3(.37,.11,.63)+cv*50.)/1300.),0.).r;
            lo+=(1.-saturate(n1b/.62))*.22*erosion*hEro;
        }
        lo=min(lo,.92);
        float d=saturate((env-lo)/(1.-lo));

        if(quality>=1){
            float fine=1.-smoothstep(7000.,26000.,dist);
            if(fine>.01){
                float n2=textureLod(cuDetail2,fract((q+cv*160.)/500.),0.).r;
                float lo2=(1.-saturate(n2/.55))*.45*erosion*fine*mix(.7,1.3,smoothstep(.2,1.,rel));
                d=saturate((d-lo2)/(1.-lo2));
            }
        }
        return d*d*(3.-2.*d);
    }

    float cuPhase(float c,float k){
        return mix(henyeyGreenstein(c,-.30*k),henyeyGreenstein(c,.80*k),.55)*4.*PI;
    }

    float cuSunScatter(float od,float c){
        float sum=0.,wsum=0.,a=1.,b=1.35,k=1.;
        for(int i=0;i<4;i++){
            sum+=a*exp(-od*b)*cuPhase(c,k);
            wsum+=a;
            a*=.5; b*=.42; k*=.55;
        }
        return sum/wsum;
    }

    float cuIsoScatter(float od){
        float sum=0.,wsum=0.,a=1.,b=1.;
        for(int i=0;i<4;i++){
            sum+=a*exp(-od*b);
            wsum+=a;
            a*=.5; b*=.5;
        }
        return sum/wsum;
    }

    float cuSunOD(vec3 wp,vec3 sd,cuweather m,float dither,float dist){
        float u=max(max(CLOUD_THICKNESS*(1.+.25*saturate(cloudRain)),1.)*.03,12.);
        float s0=.12*CLOUD_DENSITY/max(CLOUD_SCALE,.5);

        vec3 tA=normalize(cross(sd,abs(sd.y)<.99?vec3(0.,1.,0.):vec3(1.,0.,0.)));
        vec3 tB=cross(sd,tA);

        float od=0.,t=0.;
        for(int i=0;i<6;i++){
            float seg=u*exp2(float(i));
            float a=6.2831853*fract(dither+float(i)*.381966);
            vec3 off=(tA*cos(a)+tB*sin(a))*seg*.18;
            vec3 p=wp+sd*(t+seg*(.2+.6*dither))+off;
            float h=(curvedHeight(p,cameraPosition.xz,max(cameraPosition.y,1.)*R/eyeAlt(cameraPosition.y))-CLOUD_ALTITUDE*(1.-.3*saturate(cloudRain)))/max(CLOUD_THICKNESS*(1.+.25*saturate(cloudRain)),1.);
            if((h>1.&&sd.y>0.)||(h<0.&&sd.y<0.)) break;
            od+=cuDensity(p,h,m,dist,i<3?1:0)*s0*seg;
            if(od>7.) break;
            t+=seg;
        }
        return od;
    }

    float cuSkyOD(vec3 wp,float h,cuweather m,float dither){
        float th=max(CLOUD_THICKNESS*(1.+.25*saturate(cloudRain)),1.);
        float len=max((1.-h)*th,40.);
        float s0=.12*CLOUD_DENSITY/max(CLOUD_SCALE,.5);
        const float fr[3]=float[3](.18,.5,1.);
        float od=0.,prev=0.;
        for(int i=0;i<3;i++){
            float dd=len*fr[i];
            float a=6.2831853*fract(dither+float(i)*.381966);
            vec3 dir=normalize(vec3(.55*cos(a),1.,.55*sin(a)));
            vec3 p=wp+dir*(dd*(.6+.4*dither));
            od+=cuDensity(p,(curvedHeight(p,cameraPosition.xz,max(cameraPosition.y,1.)*R/eyeAlt(cameraPosition.y))-CLOUD_ALTITUDE*(1.-.3*saturate(cloudRain)))/max(CLOUD_THICKNESS*(1.+.25*saturate(cloudRain)),1.),m,1e5,0)*s0*(dd-prev);
            prev=dd;
        }
        return od;
    }

    vec4 cloudRayMarch(vec3 rd,vec3 sd,vec3 amb,vec3 sunCol,int steps){
        float base=CLOUD_ALTITUDE*(1.-.3*saturate(cloudRain));
        float th=max(CLOUD_THICKNESS*(1.+.25*saturate(cloudRain)),1.);
        float tIn,tOut;
        if(!shellIntersect(cameraPosition.y,rd,base,base+th,max(cameraPosition.y,1.)*R/eyeAlt(cameraPosition.y),tIn,tOut)) return vec4(0.);
        tOut=min(tOut,tIn+60000.);
        if(tOut<=tIn) return vec4(0.);

        float toff=fract(float(frameCounter%32)*.61803398875);
        float dither=fract(ign(gl_FragCoord.xy)+toff);
        float dither2=fract(ign(gl_FragCoord.xy+vec2(5.3,11.7))+toff*1.7);

        float rw=saturate(cloudRain);
        sunCol*=1.-.6*rw;
        amb*=1.-.3*rw;

        float LdotV=dot(rd,sd);
        float s0=.12*CLOUD_DENSITY/max(CLOUD_SCALE,.5);
        float invSteps=1./float(steps);

        vec3 acc=vec3(0.);
        float T=1.;
        float dSum=0.,wSum=0.;

        for(int j=0;j<steps;j++){
            if(T<.02) break;

            float n0=float(j)*invSteps;
            float n1=float(j+1)*invSteps;
            float dt=mix(tIn,tOut,n1*n1)-mix(tIn,tOut,n0*n0);

            float ns=(float(j)+dither)*invSteps;
            float t=mix(tIn,tOut,ns*ns);
            vec3 wp=cameraPosition+rd*t;

            float h=(curvedHeight(wp,cameraPosition.xz,max(cameraPosition.y,1.)*R/eyeAlt(cameraPosition.y))-CLOUD_ALTITUDE*(1.-.3*saturate(cloudRain)))/max(CLOUD_THICKNESS*(1.+.25*saturate(cloudRain)),1.);
            cuweather m=cuweatherAt(wp.xz);
            float dens=cuDensity(wp,h,m,t,2);
            if(dens<.004) continue;

            float sigma=dens*s0;
            float tr=exp(-sigma*dt);

            float odSun=cuSunOD(wp,sd,m,dither2,t);
            float powder=mix(1.-exp(-dens*dt*s0*6.-dens*2.),1.,saturate(LdotV*.5+.5)*.5);
            vec3 sun=sunCol*cuSunScatter(odSun,LdotV)*mix(1.,powder,.5)*CLOUD_SUNLIGHTING;

            float odUp=cuSkyOD(wp,h,m,dither2);
            float skyOcc=cuIsoScatter(odUp)*mix(.30,1.,smoothstep(0.,.7,h));
            vec3 sky=(amb*skyOcc+sunCol*(max(sd.y,0.)*.2*sq(1.-h)))*CLOUD_SKYLIGHTING;

            float thin=1.-smoothstep(0.,.5,dens);
            vec3 silver=sunCol*pow(saturate(LdotV),32.)*thin*exp(-odSun*.4)*(1.-rw)*1.5;

            vec3 col=sun+sky+silver;
            col*=mix(1.,.5+.5*smoothstep(0.,.6,h),rw);
            col=mix(col,vec3(luminance(col)),.4*rw);

            float cMax=8.*(sunCol.r+sunCol.g+sunCol.b+amb.r+amb.g+amb.b)+1.;
            col=clamp(col,vec3(0.),vec3(cMax));
            if(col!=col) col=vec3(0.);

            float w=(1.-tr)*T;
            acc+=col*w;
            dSum+=t*w;
            wSum+=w;
            T*=tr;
        }

        float alpha=1.-T;
        if(alpha<.001) return vec4(0.);

        float dMean=dSum/max(wSum,1e-5);
        float altF=exp(-max(cameraPosition.y-base,0.)*1.2e-4);
        float Tatm=exp(-dMean*2.6e-5*altF*(1.+.5*rw));
        vec3 haze=skyRadiance(rd);
        vec3 rgb=acc*Tatm+haze*alpha*(1.-Tatm);

        return vec4(rgb,alpha);
    }

    vec4 volumetricClouds(vec3 rd,int steps){
        vec3 L=lightDirection();
        vec3 light=lightColor(sunDirection())*.318;
        vec3 amb=.5*(skyRadiance(vec3(0.,1.,0.))+skyRadiance(normalize(vec3(rd.x,max(rd.y,.02),rd.z))));
        return cloudRayMarch(rd,L,amb,light,steps);
    }

#endif