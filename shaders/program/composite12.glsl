

#include "/settings.glsl"
#include "/lib/utility/uniforms.glsl"

layout(local_size_x=1) in;
const ivec3 workGroups=ivec3(1,1,1);

layout(rg32f) uniform image2D exposureImg;

void main(){
    vec2 prev=imageLoad(exposureImg,ivec2(0)).rg;
    float dt=max(frameTimeCounter-prev.g,0.);

    const int N=24;
    ivec2 res=ivec2(viewWidth,viewHeight);

    float sum=0.;
    for(int y=0;y<N;y++){
        for(int x=0;x<N;x++){
            vec2 uv=(vec2(x,y)+.5)/float(N);
            vec3 c=texelFetch(colortex0,ivec2(uv*vec2(res)),0).rgb;
            sum+=log2(dot(c,vec3(.2126,.7152,.0722))+1e-4);
        }
    }

    float avg=exp2(sum/float(N*N));

    float L=avg*.0625*2.3;

    float darkLift=1.-smoothstep(.004,.06,L);
    float key=.9*(1.+4.5*darkLift);

    float targetEV=log2(key/max(L,1e-5));
    targetEV=clamp(targetEV,EXPOSURE_MIN,EXPOSURE_MAX);

    float rate=targetEV>prev.r?3.:1.5;
    float k=1.-exp(-dt*rate);

    imageStore(exposureImg,ivec2(0),vec4(mix(prev.r,targetEV,k),frameTimeCounter,0.,0.));
}