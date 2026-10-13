#ifndef VOLUMETRIC_CLOUDS_GLSL
    #define VOLUMETRIC_CLOUDS_GLSL a

    #define CLOUD_SPEED .0001

    #include "/lib/utility/math.glsl"
    #include "/lib/utility/geometry.glsl"
    #include "/lib/utility/dithering.glsl"
    #include "/lib/utility/space.glsl"
    #include "/lib/atmosphere/scattering.glsl"

    float cloudGH(vec3 wp){
        return curvedHeight(vec3(wp.x,wp.y-243.81,wp.z),cameraPosition.xz,303381.)+243.81;
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

    float ctg(float type,float h){
        float wS=1.-saturate(type*2.);
        float wCb=saturate((type-.5)*2.);
        float wCu=1.-wS-wCb;

        float stratus=smoothstep(0.,.08,h)*(1.-smoothstep(.12,.3,h));
        float cu=smoothstep(0.,.01,h)*(1.-smoothstep(.5,.85,h));

        return stratus*wS+cu*wCu+gC(h)*wCb;
    }

    vec2 cloudCoverageMap(vec3 wp){
        float t=frameTimeCounter*CLOUD_SPEED*.1;
        vec3 p=wp*.000035/max(CLOUD_SCALE,1e-4);
        p.xz-=vec2(t,-t*.35);

        float weather=get2DNoise(p)*.6+get2DNoise(p*2.3+11.)*.4;
        float coverage=saturate(pow(max(weather,0.),1.3)*1.6-.15);

        vec3 tp=wp*.000018/max(CLOUD_SCALE,1e-4)+31.7;
        tp.xz-=vec2(t*.4,t*.15);
        float type=saturate(get2DNoise(tp)*.5+get2DNoise(tp*1.7+5.)*.5);
        type=mix(type*.6,type,coverage);

        return vec2(coverage,type);
    }

    vec2 cloudDensity(vec3 wp,float lr,float detail,int co,bool lite){
        float t=frameTimeCounter*CLOUD_SPEED*.3;

        float maxT=max(CLOUD_THICKNESS*2.2,1.);
        float gh=cloudGH(wp);
        if(gh<CLOUD_ALTITUDE||gh>CLOUD_ALTITUDE+maxT) return vec2(0.);
        float nh=saturate((gh-CLOUD_ALTITUDE)/maxT);

        vec2 weather=cloudCoverageMap(wp);
        float cov=mix(CLOUD_COVERAGE*.6,CLOUD_COVERAGE*1.4,weather.x);
        float type=weather.y;

        float ha=ctg(type,nh);
        if(ha<.0005) return vec2(0.);

        wp+=vec3(1.,0.,.3)*nh*400.*max(CLOUD_SCALE,1e-4);

        vec3 p=wp*.00045/max(CLOUD_SCALE,1e-4);
        p.xy-=vec2(t,-t*.5);

        if(!lite){
            p+=(vec3(get3DNoise(p*.5+vec3(7.,0.,0.)),get3DNoise(p*.5+vec3(0.,23.,0.)),get3DNoise(p*.5+vec3(0.,0.,41.)))-.5)*(.4*ha);
        }

        float S=2.6;
        float N=mix(.3,.55,type);
        float G=1.2;

        float base=get2DNoise(p);
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

        noise-=detail*(.5+1.1*(1.-smoothstep(0.,.65,noise)));
        noise-=erosion*.4*ha;
        noise*=ha*2.;
        noise-=ha*.9+nh*.7;
        noise=noise*(1.+nh*.6)-nh*.6;

        float x=(noise-(1.-cov))*mix(1.6,.9,saturate(noise*2.));
        float tw=mix(.22,1.15,erosion);

        return vec2(smoothstep(-tw,tw,x*20.),smoothstep(-tw,tw,x*2.))*ha*ha*CLOUD_DENSITY;
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
    
    float getSun(vec3 wp,vec3 sd,float dither){
        float far=max(4200.*CLOUD_SCALE,min(CLOUD_THICKNESS*2.2/max(sd.y,.1),12000.));
        float d1=30.*CLOUD_SCALE;
        float d2=90.*CLOUD_SCALE;
        float d3=220.*CLOUD_SCALE;

        float od=cloudDensity(wp+sd*mix(0.,d1,dither),1.,0.,1,false).y*d1;
        od+=cloudDensity(wp+sd*mix(d1,d2,dither),1.,0.,1,false).y*(d2-d1);
        od+=cloudDensity(wp+sd*mix(d2,d3,dither),1.,0.,1,false).y*(d3-d2);

        const int q=8;
        float prev=d3;
        for(int i=1;i<=q;i++){
            float edge=d3+pow(float(i)/float(q),1.5)*(far-d3);
            od+=cloudDensity(wp+sd*mix(prev,edge,dither),1.,0.,0,true).y*(edge-prev);
            prev=edge;
        }
        return od*.12;
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
            float phase=mix(henyeyGreenstein(LdotV,(-.35)*k),henyeyGreenstein(LdotV,.8*k),.65);
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
        float something=0.;

        if(something>0.){
            vec3 S=sunDirection();
            vec3 up=normalize(wp-vec3(cameraPosition.x,243.81-303381.,cameraPosition.z));
            float mu=dot(up,S);
            float hk=eyeAlt(cloudGH(wp));
            float sdh=sin(skyDip(hk));
            vec3 sunL=toRGB(sunIrr*lutT(samplerTransmittance,mu,hk*.01))*smoothstep(-sdh-.04,-sdh,mu)*.318;
            sunCol=mix(sunCol,sunL+0.,0.);
            amb*=mix(1.,.03+.97*smoothstep(-.15,.2,mu),0.);
            if(something>.5&&mu>-.04) sd=S;
        }

        int co=int((1.-smoothstep(5000.,40000.,distXZ))*2.+.5);
        float LdotV=dot(rd,sd);

        float detail=calcDetail(rd,dist*.2);
        detail=-mix(detail,0.,1./(dist*2e-5+1.));

        vec2 dens=cloudDensity(wp,1.,detail,co,false);
        float sigma=dens.x*.12;
        if(sigma<.00001) return vec4(0.);

        float h01=saturate((cloudGH(wp)-CLOUD_ALTITUDE)/max(CLOUD_THICKNESS*2.2,1.));

        float sunOD=getSun(wp,sd,dither2);
        float sunTerm=cloudMultiScatter(sunOD,LdotV);
        float skyTerm=cloudMultiScatterIso(getSkyOD(wp))*mix(.55,1.,smoothstep(0.,.7,h01));
        float under=sq(1.-h01);
        float sunL=dot(sunCol,vec3(.2722287168,.6740817658,.0536895174));
        vec3 bounce=vec3(sunL)*toAP1(vec3(.85,.92,1.))*(max(sd.y,0.)*.25*under);

        vec3 sunTint=mix(sunCol,vec3(sunL),(1.-exp(-sunOD*.5))*.7);
        float ambL=dot(amb,vec3(.2722287168,.6740817658,.0536895174));
        vec3 ambTint=mix(amb,vec3(ambL)*toAP1(vec3(.8,.92,1.12)),.6*under);

        float powder=powderEffect(dens.x,LdotV);

        vec3 col=sunTint*(sunTerm*mix(1.,powder,.5)*CLOUD_SUNLIGHTING)+(ambTint*skyTerm+bounce)*CLOUD_SKYLIGHTING;
        float silverPhase=henyeyGreenstein(LdotV,.95)*4.*PI;
        silverPhase/=1.+.15*silverPhase;
        float thin=1.-smoothstep(0.,CLOUD_DENSITY*.35,dens.x);
        col+=sunCol*silverPhase*thin*exp(-sunOD*.5)*.5;
        col*=exp2(-dist*6.5e-5*.4);
        col+=vec3(0.)*(1.-exp2(-dist*8.5e-5*.4));

        float cMax=8.*(sunCol.r+sunCol.g+sunCol.b+amb.r+amb.g+amb.b)+1.;
        col=clamp(col,vec3(0.),vec3(cMax));
        if(col!=col) col=vec3(0.);

        return vec4(col,1.-exp(-sigma*dt));
    }

    vec4 cloudRayMarch(vec3 rd,vec3 sd,vec3 amb,vec3 sunCol,int steps,float maxDist){
        float maxT=max(CLOUD_THICKNESS*2.2,1.);
        float tIn,tOut;
        if(!shellIntersect(cameraPosition.y-243.81,rd,CLOUD_ALTITUDE-243.81,CLOUD_ALTITUDE+maxT-243.81,303381.,tIn,tOut)) return vec4(0.);
        tOut=min(tOut,min(tIn+400000.,maxDist));
        if(tOut<=tIn) return vec4(0.);

        float toff=fract(float(frameCounter%32)*.61803398875);
        float dither=fract(ign(gl_FragCoord.xy)+toff);
        float dither2=fract(ign(gl_FragCoord.xy+vec2(5.3,11.7))+toff*1.7);

        vec3 acc=vec3(0.);
        float vis=1.;
        float invSteps=1./float(steps);

        for(int j=0;j<steps;j++){
            if(vis<.003) break;

            float n0=float(j)*invSteps;
            float n1=float(j+1)*invSteps;
            float dt=mix(tIn,tOut,n1*n1)-mix(tIn,tOut,n0*n0);

            float ns=(float(j)+dither)*invSteps;
            vec3 rp=cameraPosition+rd*mix(tIn,tOut,ns*ns);

            vec4 s=cloudColor(rp,sd,rd,amb,sunCol,dither2,dt);
            acc+=s.rgb*s.a*vis;
            vis*=1.-s.a;
        }

        return vec4(acc,1.-vis);
    }

    float crn(vec3 wp){
        float t=frameTimeCounter*CLOUD_SPEED*.4;
        vec3 p=wp*.00006/max(CLOUD_SCALE,1e-4);
        p.xz-=vec2(t*1.6,-t*.25);

        float n=get2DNoise(p)*.55+get2DNoise(p*3.1+8.)*.45;
        return sq(saturate(n*1.5-.55));
    }

    vec4 rm(vec3 rd,vec3 sd,vec3 amb,vec3 sunCol,int steps,float maxDist){
        vec4 res=vec4(0.);
        vec4 cl=cloudRayMarch(rd,sd,amb,sunCol,steps,maxDist);
        return vec4(res.rgb*(1.-cl.a)+cl.rgb,res.a*(1.-cl.a)+cl.a);
    }

    vec4 raymarch(vec3 rd,int steps,float maxDist){
        vec3 S=sunDirection();
        vec3 L=S.y>-.04?S:-S;
        vec3 light=lightColor(S)*.318;
        vec3 something1=moonLight(S)*.318;

        float alt=eyeAlt(cameraPosition.y);
        vec3 amb;
        if(alt>50.){
            amb=light*.06*toAP1(vec3(.7,.85,1.));
            vec3 gcf=vec3(0.);
        }else{
            amb=.5*(skyRadiance(vec3(0.,1.,0.))+skyRadiance(normalize(vec3(rd.x,max(rd.y,.02),rd.z))));
            vec3 gcf=skyRadiance(normalize(vec3(rd.x,max(rd.y,0.),rd.z)));
        }

        float gcfk=.4*exp(-alt/8.);
        float something=smoothstep(10.,40.,alt);
        return rm(rd,L,amb,light,steps,maxDist);
    }

    vec4 volumetricClouds(vec3 rd,int steps){
        return raymarch(rd,steps,1e9);
    }

#endif
