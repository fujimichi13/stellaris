#ifndef RTWSM_BLURIMPORTANCE_GLSL
    #define RTWSM_BLURIMPORTANCE_GLSL a

    #include "/lib/rtwsm/collapse.glsl"

    void rtwsmBlurImportance(int t,out float blurU,out float blurV){
        float accU=0.;
        float accV=0.;
        float wSum=0.;
        for(int k=-9;k<=9;k++){
            int j=t+k;
            if(j<0||j>=512) continue;
            float w=exp(-.5*float(k*k)/(3.*3.));
            accU+=w*rtwCollapsed[0][j];
            accV+=w*rtwCollapsed[1][j];
            wSum+=w;
        }
        blurU=accU/wSum;
        blurV=accV/wSum;
    }

#endif