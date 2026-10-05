

#ifdef vsh

    out vec2 texcoord;

    void main(){
        gl_Position=ftransform();
        texcoord=(gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;
    }

#endif

#ifdef fsh

    #include "/settings.glsl"
    #include "/lib/utility/uniforms.glsl"

    in vec2 texcoord;

    /* RENDERTARGETS:0 */
    layout(location = 0) out vec4 color;

    vec3 ACES(vec3 v){
        v=mat3(.59719,.0760,.0284,.35458,.90834,.13383,.04823,.01566,.83777)*max(v,0.)*.0625;
        v=(v*(v+.0245786)-.000090537)/(v*(.983729*v+.432951)+.238081);
        return clamp(mat3(1.60475,-.10208,-.00327,-.53108,1.10813,-.07276,-.07367,-.00605,1.07602)*v,0.,1.);
    }

    const float K3[3]=float[3](.25,.5,.25);

    void main(){
        ivec2 px=ivec2(gl_FragCoord.xy);
        vec4 base=texelFetch(colortex8,px,0);
        vec4 wgt=texelFetch(colortex7,px,0);

        if(wgt.a>.5){
            color=base;
            return;
        }

        vec3 gi=vec3(0.);

        #ifdef RSM_ENABLED
            ivec2 fullRes=textureSize(colortex3,0);
            ivec2 hres=fullRes>>1;
            ivec2 hp=px>>1;

            float depth=texelFetch(depthtex0,px,0).r;
            vec4 v=gbufferProjectionInverse*vec4(texcoord*2.-1.,depth*2.-1.,1.);
            float d0=length((gbufferModelViewInverse*vec4(v.xyz/v.w,1.)).xyz);
            vec3 n0=normalize(texelFetch(colortex3,px,0).xyz);

            vec4 h0=texelFetch(colortex5,hp,0);
            int s=(h0.a<6.)?2:1;
            
            vec3 sum=vec3(0.);
            float wsum=0.;

            for(int y=-1;y<=1;y++){
                for(int x=-1;x<=1;x++){
                    ivec2 q=hp+ivec2(x,y)*s;
                    if(any(lessThan(q,ivec2(0)))||any(greaterThanEqual(q,hres))) continue;

                    float dq=texelFetch(colortex6,q,0).r;
                    if(dq<=0.) continue;

                    vec3 gq=texelFetch(colortex5,q,0).rgb;
                    if(any(isnan(gq))) continue;

                    vec3 nq=normalize(texelFetch(colortex3,min(q*2,fullRes-1),0).xyz);

                    float w=K3[x+1]*K3[y+1];
                    w*=pow(max(dot(n0,nq),0.),24.);
                    w*=exp(-abs(dq-d0)/(.04*d0*float(s)+.05));

                    sum+=gq*w;
                    wsum+=w;
                }
            }

            gi=(wsum>1e-4)?sum/wsum:h0.rgb;
            gi*=wgt.rgb;
        #endif

        vec3 hdr=base.rgb+gi;
        //color=vec4(pow(ACES(hdr),vec3(.4545455)),base.a);
        color=vec4(base.rgb+gi,base.a);
    }

#endif