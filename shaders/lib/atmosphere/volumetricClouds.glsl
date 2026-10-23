#ifndef VOLUMETRIC_CLOUDS_GLSL
    #define VOLUMETRIC_CLOUDS_GLSL a

    #define CLOUD_SPEED .0001

    #include "/lib/utility/math.glsl"
    #include "/lib/utility/geometry.glsl"
    #include "/lib/utility/dithering.glsl"
    #include "/lib/utility/space.glsl"
    #include "/lib/atmosphere/scattering.glsl"

    float cloudPR(){
        return max(cameraPosition.y,1.)*R/eyeAlt(cameraPosition.y);
    }

    float get2DNoise(in vec3 pos){
    	pos.xy=pos.xz;
    	pos.xy+=.5;

    	vec2 p=floor(pos.xy);
    	vec2 f=fract(pos.xy);
    	f=smoothstep(vec2(0.),vec2(1.),f);
    	vec2 uv=p.xy+f.xy;

    	vec2 coord=(uv+.5f)/64;
    	float xy1=texture2D(noisetex1,coord).x;
    	return xy1;
    }
    float get3DNoise(in vec3 pos){
        pos+=.5;

    	vec3 p=floor(pos);
    	vec3 f=fract(pos);
    	f=curve(f);

    	vec2 uv=p.xy+p.z*vec2(-17.)+f.xy;
    	vec2 uv1=p.xy+(p.z+0.)*vec2(-17.)+f.xy;

    	vec2 coord=(uv+.5)/64.;
    	vec2 coord1=(uv1+.5)/64.;
    	float rr=texture2D(noisetex1,coord).x;
    	float gg=texture2D(noisetex1,coord1).y;
    	return mix(rr,gg,f.z);
    }
    float get3DNoise2(in vec3 pos){
        pos+=.5;
    	vec3 p=floor(pos);
    	vec3 f=fract(pos);
    	f=curve(f);

    	vec2 uv=p.xy+p.z*vec2(17.)+f.xy;
    	vec2 uv1=p.xy+(p.z+1.)*vec2(17.)+f.xy;
    	vec2 coord=(uv+.5)/64.;
    	vec2 coord1=(uv1+.5)/64.;
    	float rr=abs(texture2D(noisetex1,coord).x*3.-2.)*.879;
    	float gg=abs(texture2D(noisetex1,coord1).x*3.-2.)*.879;
    	return mix(rr,gg,f.z);
    }
    float STRNoise(in vec3 pos){
    	pos.z+=0.;
    	pos.xyz+=.5;

    	vec3 p=floor(pos);
    	vec3 f=fract(pos);

    	vec2 uv=p.xy+p.z*vec2(-17.)+f.xy;
    	vec2 uv2=p.xy+(p.z+0.)*vec2(1.)+f.xy;

    	vec2 coord=(uv+.5)/64.;
    	vec2 coord2=(uv2+.5)/64.;
    	float xy1=texture2D(noisetex1,coord).x;
    	float xy2=texture2D(noisetex1,coord2).g;
    	return mix(1.,xy2,f.z);
    }

    float evalDraine(float u,float g,float a){
        return ((1.-g*g)*(1.+a*u*u))/(4.*(1.+(a*(1.+2.*g*g))/3.)*PI*pow(max(1.+g*g-2.*g*u,1e-4),1.5));
    }

    float cloudPhase(float cosT){
        return mix(henyeyGreenstein(cosT,(-.35)),henyeyGreenstein(cosT,.8),.65);
    }

    float powderEffect(float density,float LdotV){
        return mix(1.-exp2(-density*2.5),1.,saturate(LdotV*.5+.5)*.5);
    }

    float gC(float h){
        float body=smoothstep(0.,.08,h)*(1.-smoothstep(.75,.92,h));
        float anvil=smoothstep(.65,.8,h)*(1.-smoothstep(.9,1.,h))*.6;
        return max(body,anvil);
    }

    float ctg(float type,float h,float cv){
        float wS=1.-saturate(type*2.);
        float wCb=saturate((type-.5)*2.);
        float wCu=1.-wS-wCb;

        float stratus=smoothstep(0.,.08,h)*(1.-smoothstep(.12,.3,h));
        float hh=h/mix(.3,1.15,saturate(cv));
        float cu=smoothstep(0.,.03,h)*(1.-smoothstep(.5,.95,hh));

        float base=stratus*wS+cu*wCu+gC(h)*wCb;
        float nimbus=smoothstep(0.,.05,h)*(1.-smoothstep(.6,.95,h));
        return mix(base,max(base,nimbus),saturate(cloudRain));
    }

    vec2 cloudCoverageMap(vec3 wp){
        float S=max(CLOUD_SCALE,1e-4);
        float t=frameTimeCounter*CLOUD_SPEED*.1;
        float dXZ=length(wp.xz-cameraPosition.xz)/S;

        vec3 p=wp*.00003/S;
        p.xz-=vec2(t,-t*.35);

        float macro=get2DNoise(p)*.6+get2DNoise(p*2.1+5.)*.4;
        float cellN=get2DNoise(p*12.+11.)*.6+get2DNoise(p*26.+23.)*.4;

        float nearW=1.-smoothstep(1500.,22000.,dXZ);
        float farW=smoothstep(25000.,80000.,dXZ);

        float regional=smoothstep(.3,.7,macro);
        float thr=mix(.6,.52,regional)-nearW*.04+farW*.06;
        float coverage=smoothstep(thr-.04,thr+.25,cellN);

        vec3 tp=wp*.000018/S+31.7;
        tp.xz-=vec2(t*.4,t*.15);
        float type=saturate(get2DNoise(tp)*.5+get2DNoise(tp*1.7+5.)*.5);
        type=saturate(.5+(type-.5)*.2+max(coverage-.7,0.)*.4);

        float r=saturate(cloudRain);
        coverage=mix(coverage,saturate(coverage*.4+.7),r);
        type=mix(type,.55+type*.25,r);

        return vec2(coverage,type);
    }

    vec2 cloudDensity(vec3 wp,float lr,float detail,int co,bool lite){
        float t=frameTimeCounter*CLOUD_SPEED*.3;

        float maxT=max(CLOUD_THICKNESS*2.2*(1.+.25*saturate(cloudRain)),1.);
        float gh=curvedHeight(wp,cameraPosition.xz,cloudPR());
        if(gh<(CLOUD_ALTITUDE*(1.-.35*saturate(cloudRain)))||gh>(CLOUD_ALTITUDE*(1.-.35*saturate(cloudRain)))+maxT) return vec2(0.);
        float nh=saturate((gh-(CLOUD_ALTITUDE*(1.-.35*saturate(cloudRain))))/maxT);

        vec2 weather=cloudCoverageMap(wp);
        if(weather.x<.03) return vec2(0.);
        float cov=mix(CLOUD_COVERAGE*.6,CLOUD_COVERAGE*1.4,weather.x)*(1.+.35*saturate(cloudRain));
        float type=weather.y;

        float ha=ctg(type,nh,weather.x);
        if(ha<.0005) return vec2(0.);

        wp+=vec3(1.,0.,.3)*nh*400.*max(CLOUD_SCALE,1e-4);

        vec3 p=wp*vec3(.0004,.0002,.0004)/max(CLOUD_SCALE,1e-4);
        p.xy-=vec2(t,-t*.5);

        if(!lite){
            p+=(vec3(get3DNoise(p*.5+vec3(7.,0.,0.)),get3DNoise(p*.5+vec3(0.,23.,0.)),get3DNoise(p*.5+vec3(0.,0.,41.)))-.5)*(.4*ha);
        }

        float S=2.6;
        float N=mix(.3,.55,type);
        float G=1.2;

        float base=mix(get2DNoise(p),get3DNoise(p*1.3),.7);
        float noise=lite?base*.9:mix(base,base*STRNoise(vec3(p.xy,nh*4.)),.5)*.9;

        int oct=lite?3:3+co;
        for(int j=1;j<oct;j++){
            p*=S;
            G*=N*lr;
            noise+=(get3DNoise(p)-.5)*G;
        }

        float erosion=0.;
        if(!lite){
            float rc=1.-abs(get3DNoise(p*.6+vec3(4.4,0.,0.))*2.-1.);
            float rf=1.-abs(get3DNoise(p*3.1+vec3(0.,9.1,0.))*2.-1.);
            float edge=1.-abs(saturate(noise*1.5)*2.-1.);
            erosion=(rc*.7+rf*.3)*edge;
        }

        noise-=detail*(.5+1.1*(1.-smoothstep(0.,.65,noise)))*(1.-.4*saturate(cloudRain));
        noise-=erosion*.4*ha;
        noise*=ha*2.;
        noise-=ha*.9+nh*.7;
        noise=noise*(1.+nh*.6)-nh*.6;

        float x=(noise-(1.-cov))*mix(1.6,.9,saturate(noise*2.));
        float tw=mix(.22,1.15,erosion);

        float nearBoost=1.+.6*(1.-smoothstep(2000.,25000.,length(wp.xz-cameraPosition.xz)/max(CLOUD_SCALE,1e-4)));

        return vec2(smoothstep(-tw,tw,x*20.),smoothstep(-tw,tw,x*2.))*ha*ha*CLOUD_DENSITY*(1.+1.5*saturate(cloudRain))*nearBoost;
    }

    bool cloudEmpty(vec3 wp){
        float maxT=max(CLOUD_THICKNESS*2.2*(1.+.25*saturate(cloudRain)),1.);
        float gh=curvedHeight(wp,cameraPosition.xz,cloudPR());
        if(gh<(CLOUD_ALTITUDE*(1.-.35*saturate(cloudRain)))||gh>(CLOUD_ALTITUDE*(1.-.35*saturate(cloudRain)))+maxT) return true;
        float nh=saturate((gh-(CLOUD_ALTITUDE*(1.-.35*saturate(cloudRain))))/maxT);
        vec2 cm=cloudCoverageMap(wp);
        return cm.x<.03||ctg(cm.y,nh,cm.x)<.0005;
    }

    float calcDetail(vec3 wd,float dist){
        vec3 curl=vec3(get3DNoise(wd*3.),get3DNoise(wd*3.+19.),get3DNoise(wd*3.+37.))-.5;
        vec3 pos=wd+curl*.18;

        float n=(.5-get3DNoise2(pos*50.))*2./(1.+dist*1e-3*1.6);
        n+=(.5-get3DNoise2(pos*100.))/(1.+dist*1e-4*8.);
        n+=(.5-get3DNoise2(pos*200.))*.5/(1.+dist*1e-4*4.);
        n+=(.5-get3DNoise2(pos*400.))*.25/(1.+dist*1e-4*2.);
        n+=(.5-get3DNoise2(pos*800.))*.125/(1.+dist*1e-4);
        return n*(dist*1e-4*2.+1.);
    }
    
    float cloudTopProxy(vec3 wp){
        vec2 cm=cloudCoverageMap(wp);
        return cm.x*mix(.25,.9,cm.y);
    }

    vec2 cloudBoundaryTop(vec3 wp,vec3 sd,float maxT){
        float S=max(CLOUD_SCALE,1e-4);
        float hx=curvedHeight(wp,cameraPosition.xz,cloudPR());
        float dTop=clamp(((CLOUD_ALTITUDE*(1.-.35*saturate(cloudRain)))+maxT*.6-hx)/max(abs(sd.y),.15)*sign(sd.y+1e-5),0.,2500.*S);
        vec3 pe=wp+sd*dTop;
        float e=600.*S;
        float h0=cloudTopProxy(pe);
        float hX=cloudTopProxy(pe+vec3(e,0.,0.));
        float hZ=cloudTopProxy(pe+vec3(0.,0.,e));
        vec3 N=normalize(vec3(-(hX-h0)*maxT/e,1.,-(hZ-h0)*maxT/e));
        float w=.6;
        float wrap=saturate((dot(N,sd)+w)/(1.+w));
        float ct=mix(1.,wrap,.7);
        return vec2(ct,saturate(cloudTopProxy(wp)/.9));
    }

    vec2 getSun(vec3 wp,vec3 sd,float dither){
        float far=4200.*CLOUD_SCALE;
        float d1=40.*CLOUD_SCALE*(.75+.5*dither);
        float d2=140.*CLOUD_SCALE*(.75+.5*dither);
        float maxT=max(CLOUD_THICKNESS*2.2*(1.+.25*saturate(cloudRain)),1.);

        const int q=6;
        const int NS=q+2;
        float sDist[NS];
        float sLen[NS];
        float sSig[NS];

        sDist[0]=d1; sLen[0]=d1;
        sSig[0]=cloudDensity(wp+sd*d1,1.,0.,1,false).y*.12;
        sDist[1]=d2; sLen[1]=d2-d1;
        sSig[1]=cloudDensity(wp+sd*d2,1.,0.,1,false).y*.12;

        float prev=d2;
        for(int i=1;i<=q;i++){
            float u=(float(i)-1.+.15+.7*dither)/float(q);
            float dist=d2+pow(u,1.5)*(far-d2);
            sDist[i+1]=dist;
            sLen[i+1]=max(dist-prev,0.);
            prev=dist;
            sSig[i+1]=cloudDensity(wp+sd*dist,1.,0.,0,true).y*.12;
        }

        float odc[NS];
        float cum=0.;
        for(int j=0;j<NS;j++){
            float odj=sSig[j]*sLen[j];
            odc[j]=cum+.5*odj;
            cum+=odj;
        }
        float odTot=cum;

        float phi=0.;
        if(odTot>.02){
            vec2 bt=cloudBoundaryTop(wp,sd,maxT);
            float Hcol=bt.y;
            float Hsoft=.25*mix(1.,4.,Hcol);
            float sigRef=.12*CLOUD_DENSITY;

            for(int j=0;j<NS;j++){
                float odj=sSig[j]*sLen[j];
                if(odj<1e-4) continue;
                
                float tauE=max(odTot-odc[j],0.);

                float Tabs=exp(-.001*tauE);
                float Ciso=1.-exp(-.2*tauE);
                float sTr=saturate(sSig[j]/max(sigRef,1e-5));

                float hs=curvedHeight(wp+sd*sDist[j],cameraPosition.xz,cloudPR());
                float hloc=saturate((hs-(CLOUD_ALTITUDE*(1.-.35*saturate(cloudRain))))/maxT)/max(Hcol*.9,.12);
                float Cbot=1.-exp(-max(hloc,0.)/Hsoft*1.5);

                float kern=exp(-.05477*odc[j])/max(sDist[j]*sigRef,1.);

                phi+=Tabs*odj*sTr*Ciso*Cbot*kern;
            }
            phi*=bt.x;
        }

        return vec2(odTot,phi);
    }

    float getSkyOD(vec3 wp){
        const int q=3;
        float od=0.;
        float prev=0.;
        for(int i=1;i<=q;i++){
            float dist=pow(float(i)/float(q),1.5)*2400.;
            float len=dist-prev;
            prev=dist;
            od+=cloudDensity(wp+vec3(0.,dist,0.),.75,-.1,0,true).y*len;
        }
        return od*.12;
    }

    float cloudMultiScatter(float od,float LdotV){
        float sum=0.;
        float wsum=0.;
        float a=1.;
        float b=1.;
        float k=1.;

        for(int i=0;i<4;i++){
            float phase=mix(henyeyGreenstein(LdotV,(-.35)*k),evalDraine(LdotV,.8*k,5.*k),.65);
            float p4=phase*4.*PI;
            phase=1.1*p4/(1.+.1*p4);
            
            sum+=a*exp(-od*b)*phase;
            wsum+=a;
            a*=.5;
            b*=.5;
            k*=.5;
        }
        return sum/max(wsum,1e-4);
    }

    float cloudMultiScatterIso(float od){
        float sum=0.;
        float wsum=0.;
        float a=1.;
        float b=1.;

        for(int i=0;i<4;i++){
            sum+=a*exp(-od*b);
            wsum+=a;
            a*=.5;
            b*=.5;
        }
        return sum/max(wsum,1e-4);
    }

    vec4 cloudColor(vec3 wp,vec3 sd,vec3 rd,vec3 amb,vec3 sunCol,float dither2,float dt){
        float distXZ=length(wp.xz-cameraPosition.xz)/max(CLOUD_SCALE,1e-4);
        float dist=length(wp-cameraPosition)/max(CLOUD_SCALE,1e-4);

        float rw=saturate(cloudRain);
        sunCol*=1.-.6*rw;
        amb*=1.-.3*rw;

        int co=int((1.-smoothstep(5000.,40000.,distXZ))*2.+.5);
        float LdotV=dot(rd,sd);

        if(cloudEmpty(wp)) return vec4(0.);

        float dd=min(dist,60000.);
        float detail=calcDetail(rd,dd*.2);
        detail=-mix(detail,0.,1./(dd*2e-5+1.));

        vec2 dens=cloudDensity(wp,1.,detail,co,false);
        float sigma=dens.x*.12;
        if(sigma<.00001) return vec4(0.);
        float alphaC=1.-exp(-sigma*dt);
        if(alphaC<.0015) return vec4(0.);

        float h01=saturate((curvedHeight(wp,cameraPosition.xz,cloudPR())-(CLOUD_ALTITUDE*(1.-.35*saturate(cloudRain))))/max(CLOUD_THICKNESS*2.2*(1.+.25*saturate(cloudRain)),1.));

        vec2 sunPhi=getSun(wp,sd,dither2);
        float sunOD=sunPhi.x;
        float sunTerm=cloudMultiScatter(sunOD,LdotV);
        float skyTerm=cloudMultiScatterIso(getSkyOD(wp))*mix(.55,1.,smoothstep(0.,.7,h01));
        vec3 bounce=sunCol*(max(sd.y,0.)*.25*sq(1.-h01));

        float powder=powderEffect(dens.x,LdotV);
        float phiFwd=sunPhi.y*.6;

        vec3 col=sunCol*(sunTerm*mix(1.,powder,.5)*CLOUD_SUNLIGHTING)+(amb*skyTerm+bounce)*CLOUD_SKYLIGHTING;
        col+=sunCol*phiFwd*CLOUD_SUNLIGHTING;
        float fwd=pow(saturate(LdotV),10.);
        float thin=1.-smoothstep(0.,.55,dens.x);
        float silver=(fwd+4.*pow(saturate(LdotV),48.))*(.2+.8*thin)*exp(-sunOD*.35)*(1.-.4*h01)*(1.-rw)*2.;
        col+=sunCol*silver;
        col*=mix(1.,.5+.5*smoothstep(0.,.6,h01),rw);
        col=mix(col,vec3(dot(col,vec3(.2126,.7152,.0722))),.4*rw);
        float air=min(dist,60000.)*exp2(-max(cameraPosition.y-(CLOUD_ALTITUDE*(1.-.35*saturate(cloudRain))),0.)*1.8e-4);
        col*=exp2(-air*6.5e-5);
        col+=amb*(1.-exp2(-air*8.5e-5));

        float cMax=8.*(sunCol.r+sunCol.g+sunCol.b+amb.r+amb.g+amb.b)+1.;
        col=clamp(col,vec3(0.),vec3(cMax));
        if(col!=col) col=vec3(0.);

        return vec4(col,alphaC);
    }

    vec4 cloudRayMarch(vec3 rd,vec3 sd,vec3 amb,vec3 sunCol,int steps){
        float maxT=max(CLOUD_THICKNESS*2.2*(1.+.25*saturate(cloudRain)),1.);
        float tIn,tOut;
        if(!shellIntersect(cameraPosition.y,rd,(CLOUD_ALTITUDE*(1.-.35*saturate(cloudRain))),(CLOUD_ALTITUDE*(1.-.35*saturate(cloudRain)))+maxT,cloudPR(),tIn,tOut)) return vec4(0.);
        tOut=min(tOut,tIn+100000.);
        if(tOut<=tIn) return vec4(0.);

        float toff=fract(float(frameCounter%32)*.61803398875);
        float dither=fract(ign(gl_FragCoord.xy)+toff);
        float dither2=fract(ign(gl_FragCoord.xy+vec2(5.3,11.7))+toff*1.7);

        vec3 shaft=vec3(0.);
        vec3 sS=sunDirection();
        if(sS.y>0.){
            float mc=-dot(rd,sS);
            float rp=RayleighPhaseFunction(mc);
            float ap=AerosolPhaseFunction(mc);
            float kmH=length(rd.xz)*.001;
            float cb=CLOUD_ALTITUDE*(1.-.35*saturate(cloudRain));
            vec4 tauV=vec4(0.);
            vec4 loss=vec4(0.);
            for(int i=0;i<8;i++){
                float ta=tOut*sq(float(i)/8.);
                float tb=tOut*sq(float(i+1)/8.);
                vec3 sp=cameraPosition+rd*mix(ta,tb,dither);
                float h=eyeAlt(sp.y);
                float ds=length(vec2(kmH*(tb-ta),eyeAlt(cameraPosition.y+rd.y*tb)-eyeAlt(cameraPosition.y+rd.y*ta)));
                vec4 rS,aS,ex;
                coefficients(h,rS,aS,ex);
                vec4 Tv=exp(-(tauV+ex*ds*.5));
                tauV+=ex*ds;

                float sh=curvedHeight(sp,cameraPosition.xz,cloudPR());
                float dA=max((cb-sh)/max(sS.y,.02),0.);
                float dB=min((cb+maxT-sh)/max(sS.y,.02),dA+12000.*CLOUD_SCALE);
                float od=0.;
                if(dB>dA){
                    for(int k=0;k<3;k++) od+=cloudDensity(sp+sS*mix(dA,dB,(float(k)+dither2)/3.),1.,0.,0,true).x*.12*(dB-dA)/3.;
                }
                loss+=Tv*sunIrr*lutT(samplerTransmittance,sS.y,h*.01)*(rS*rp+aS*ap)*(1.-exp(-od))*ds;
            }
            shaft=toRGB(loss)*smoothstep(0.,.1,sS.y);
            shaft*=min(1.,.5/max(dot(shaft,vec3(.2126,.7152,.0722)),1e-4));
        }

        vec3 acc=vec3(0.);
        float vis=1.;
        float invSteps=1./float(steps);

        for(int j=0;j<steps;j++){
            if(vis<.01) break;

            float n0=float(j)*invSteps;
            float n1=float(j+1)*invSteps;
            float dt=mix(tIn,tOut,n1*n1)-mix(tIn,tOut,n0*n0);

            float ns=(float(j)+dither)*invSteps;
            vec3 rp=cameraPosition+rd*mix(tIn,tOut,ns*ns);

            vec4 s=cloudColor(rp,sd,rd,amb,sunCol,dither2,dt);
            acc+=s.rgb*s.a*vis;
            vis*=1.-s.a;
        }

        return vec4(acc-shaft*vis,1.-vis);
    }

    float crn(vec3 wp){
        float t=frameTimeCounter*CLOUD_SPEED*.4;
        vec3 p=wp*.00006/max(CLOUD_SCALE,1e-4);
        p.xz-=vec2(t*1.6,-t*.25);

        float n=get2DNoise(p)*.55+get2DNoise(p*3.1+8.)*.45;
        return sq(saturate(n*1.5-.55));
    }

    vec4 rm(vec3 rd,vec3 sd,vec3 amb,vec3 sunCol,int steps){
        vec4 res=vec4(0.);
        vec4 cl=cloudRayMarch(rd,sd,amb,sunCol,steps);
        return vec4(res.rgb*(1.-cl.a)+cl.rgb,res.a*(1.-cl.a)+cl.a);
    }

    vec4 volumetricClouds(vec3 rd,int steps){
        vec3 L=lightDirection();
        vec3 light=lightColor(sunDirection())*.318;
        vec3 amb=.5*(skyRadiance(vec3(0.,1.,0.))+skyRadiance(normalize(vec3(rd.x,max(rd.y,.02),rd.z))));

        return rm(rd,L,amb,light,steps);
    }

#endif