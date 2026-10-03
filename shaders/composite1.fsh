#version 430 compatibility

#define RSM_ENABLED

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D colortex6;
uniform sampler2D colortex7;
uniform sampler2D colortex8;

in vec2 texcoord;

/* RENDERTARGETS:0 */
layout(location = 0) out vec4 color;

vec3 ACES(vec3 v){
    v=mat3(.59719,.0760,.0284,.35458,.90834,.13383,.04823,.01566,.83777)*max(v,0.)*.0625;
    v=(v*(v+.0245786)-.000090537)/(v*(.983729*v+.432951)+.238081);
    return clamp(mat3(1.60475,-.10208,-.00327,-.53108,1.10813,-.07276,-.07367,-.00605,1.07602)*v,0.,1.);
}

const float K[5]=float[5](1./16.,4./16.,6./16.,4./16.,1./16.);

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
        vec4 h0=texelFetch(colortex5,px,0);
        float d0=texelFetch(colortex6,px,0).r;
        vec3 n0=normalize(texelFetch(colortex3,px,0).xyz);

        int s=(h0.a<4.)?3:(h0.a<12.)?2:1;

        ivec2 res=textureSize(colortex5,0);
        vec3 sum=vec3(0.);
        float wsum=0.;

        for(int y=-2;y<=2;y++){
            for(int x=-2;x<=2;x++){
                ivec2 q=px+ivec2(x,y)*s;
                if(any(lessThan(q,ivec2(0)))||any(greaterThanEqual(q,res))) continue;

                float dq=texelFetch(colortex6,q,0).r;
                if(dq<=0.) continue;
                
                vec3 nq=normalize(texelFetch(colortex3,q,0).xyz);
                vec3 gq=texelFetch(colortex5,q,0).rgb;
                if(any(isnan(gq))) continue;

                float w=K[x+2]*K[y+2];
                w*=pow(max(dot(n0,nq),0.),24.);                       // normal edge stop
                w*=exp(-abs(dq-d0)/(.02*d0*float(s)+.05));            // depth edge stop

                sum+=gq*w;
                wsum+=w;
            }
        }

        gi=(wsum>1e-4)?sum/wsum:h0.rgb;
        gi*=wgt.rgb;
    #endif

    vec3 hdr=base.rgb+gi;
    color=vec4(pow(ACES(hdr),vec3(.4545455)),base.a);
}