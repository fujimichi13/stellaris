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

    float cloudPR;
    float cloudBottom;
    float cloudDepth;
    float cloudSigma;

    float cloudHeight(vec3 p){
        return (curvedHeight(p,cameraPosition.xz,cloudPR)-cloudBottom)/cloudDepth;
    }

    float cloudDensityAt(vec3 p,float h,int q){
        if(h<=0.||h>=1.) return 0.;
        cuweather m=cuweatherAt(p.xz);
        return cuDensity(p,h,m,length(p-cameraPosition),q);
    }

    float freeFlight(){
        return -log(max(1.-rand(),1e-6))/cloudSigma;
    }

    float cloudPhase(float c){
        return mix(henyeyGreenstein(c,-.30),henyeyGreenstein(c,.80),.55);
    }

    float hgNorm(float c,float g){
        float d=1.+g*g-2.*g*c;
        return (1.-g*g)/(12.566370614*d*sqrt(max(d,1e-6)));
    }

    float cloudPhasePdf(float c){
        return mix(hgNorm(c,-.30),hgNorm(c,.80),.55);
    }

    float skyNeePdf(vec3 w){
        return ((w.y>0.)?.75:1.-.75)/TAU;
    }

    float cloudTransmittance(vec3 o,vec3 dir,int maxSteps,out int side){
        float T=1.;
        float s=0.;
        side=1;
        for(int i=0;i<maxSteps;i++){
            float ds=freeFlight();
            float fl=5.+.35*s;
            bool exact=ds>=fl;
            float x=s+(exact?ds:fl*rand());

            vec3 p=o+dir*x;
            float h=cloudHeight(p);
            if(h>=1.) return T;
            if(h<=0.){
                side=2;
                return T;
            }

            float d=cloudDensityAt(p,h,1);
            T*=exact?(1.-d):exp(-cloudSigma*d*fl);

            if(T<.1){
                if(rand()*.1>T) return 0.;
                T=.1;
            }
            s+=exact?ds:fl;
        }
        return T;
    }

    float sunTransmittance(vec3 o,vec3 L){
        int side;
        return cloudTransmittance(o,L,20,side);
    }

    vec4 volumetricClouds(vec3 rd,int steps,int bounces,int samples,uint salt){
        float rw=saturate(cloudRain);
        cloudPR=max(cameraPosition.y,1.)*R/eyeAlt(cameraPosition.y);
        cloudBottom=CLOUD_ALTITUDE*(1.-.3*rw);
        cloudDepth=max(CLOUD_THICKNESS*(1.+.25*rw),1.);
        cloudSigma=max(.12*CLOUD_DENSITY/max(CLOUD_SCALE,.5)*(1.+.5*rw),1e-4);

        float tIn,tOut;
        if(!shellIntersect(cameraPosition.y,rd,cloudBottom,cloudBottom+cloudDepth,cloudPR,tIn,tOut)) return vec4(0.);
        tOut=min(tOut,tIn+60000.);
        if(tOut<=tIn) return vec4(0.);

        vec3 L=lightDirection();
        vec3 E=lightColor(sunDirection());
        vec3 amb=skyAmbient();
        vec3 ground=.25*(E*(max(L.y,0.)*.31830989)+amb);
        float clampL=6.*luminance(E)+8.*luminance(amb)+1.;
        vec3 haze=skyRadiance(rd);
        float altF=exp(-max(cameraPosition.y-cloudBottom,0.)*1.2e-4);
        float f0=.5*(tOut-tIn)/float(steps);

        uint saved=state;
        state=pcg(uint(gl_FragCoord.x)+pcg(uint(gl_FragCoord.y)+pcg(uint(frameCounter)+salt)));

        vec4 acc=vec4(0.);
        for(int n=0;n<samples;n++){
            float tHit=tIn;
            bool found=false;
            float t=tIn;
            for(int i=0;i<steps;i++){
                float ds=freeFlight();
                float fl=f0+.04*(t-tIn);
                bool exact=ds>=fl;
                float x=t+(exact?ds:fl*rand());
                if(x>=tOut) break;

                vec3 q=cameraPosition+rd*x;
                float d=cloudDensityAt(q,cloudHeight(q),2);
                bool hit=exact?(rand()<d):(rand()<1.-exp(-cloudSigma*d*fl));
                if(hit){
                    tHit=x;
                    found=true;
                    break;
                }
                t+=exact?ds:fl;
            }
            if(!found) continue;

            vec3 p=cameraPosition+rd*tHit;
            vec3 w=rd;
            vec3 Lo=vec3(0.);

            for(int b=0;b<=bounces;b++){
                bool last=(b==bounces);

                if(L.y>0.){
                    Lo+=E*(cloudPhase(dot(w,L))*sunTransmittance(p,L)*CLOUD_SUNLIGHTING);
                }

                float upF=(rand()<.75)?1.:-1.;
                float ny=upF*rand();
                float nr=sqrt(max(1.-ny*ny,0.));
                float nphi=TAU*rand();
                vec3 wn=vec3(nr*cos(nphi),ny,nr*sin(nphi));

                float pdfN=skyNeePdf(wn);
                float pdfP=cloudPhasePdf(dot(w,wn));

                int nside;
                float Tn=cloudTransmittance(p,wn,12,nside);
                if(Tn>0.){
                    vec3 envL=(nside==1)?skyRadiance(wn):ground;
                    float mwN=last?1.:(pdfN*pdfN)/(pdfN*pdfN+pdfP*pdfP);
                    Lo+=envL*(Tn*pdfP/pdfN*mwN*CLOUD_SKYLIGHTING);
                }

                if(last) break;

                float g=(rand()<.55)?.80:-.30;
                float k=(1.-g*g)/(1.-g+2.*g*rand());
                float c=clamp((1.+g*g-k*k)/(2.*g),-1.,1.);
                float phi=TAU*rand();
                vec3 bt,bb;
                basis(w,bt,bb);
                w=normalize(w*c+(bt*cos(phi)+bb*sin(phi))*sqrt(max(1.-c*c,0.)));
                float pdfPrev=cloudPhasePdf(c);

                int r=1;
                vec3 pn=p;
                float s=0.;
                for(int i=0;i<24;i++){
                    float ds=freeFlight();
                    float fl=4.+.3*s;
                    bool exact=ds>=fl;
                    float x=s+(exact?ds:fl*rand());

                    vec3 q=p+w*x;
                    float h=cloudHeight(q);
                    if(h>=1.){
                        r=1;
                        break;
                    }
                    if(h<=0.){
                        r=2;
                        break;
                    }

                    float d=cloudDensityAt(q,h,1);
                    bool hit=exact?(rand()<d):(rand()<1.-exp(-cloudSigma*d*fl));
                    if(hit){
                        pn=q;
                        r=0;
                        break;
                    }
                    s+=exact?ds:fl;
                }

                if(r==0){
                    p=pn;
                    continue;
                }

                float mwP=1.;
                float pdfN2=skyNeePdf(w);
                mwP=(pdfPrev*pdfPrev)/(pdfPrev*pdfPrev+pdfN2*pdfN2);
                Lo+=((r==1)?skyRadiance(w):ground)*(CLOUD_SKYLIGHTING*mwP);
                break;
            }

            Lo=min(Lo,vec3(clampL));
            if(Lo!=Lo) Lo=vec3(0.);

            float Tatm=exp(-tHit*2.6e-5*altF*(1.+.5*rw));
            acc+=vec4(Lo*Tatm+haze*(1.-Tatm),1.);
        }

        state=saved;
        return acc/float(samples);
    }

#endif