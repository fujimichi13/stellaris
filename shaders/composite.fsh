#version 430 compatibility

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform sampler2D shadowtex1;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowModelView;
uniform vec3 shadowLightPosition;

uniform sampler2D samplerWarpX;
uniform sampler2D samplerWarpY;

uniform sampler2D noisetex;

layout(r32ui) uniform uimage2D histX;
layout(r32ui) uniform uimage2D histY;

in vec2 texcoord;

/* RENDERTARGETS:0 */
layout(location = 0) out vec4 color;

const float sunPathRotation = -40.0;

const int shadowMapResolution = 2048;
const float shadowDistance = 192.0;

float rtwsmWarp1D(sampler2D tex, float u, out float slope){
    slope=1.;
    if(u<=0.||u>=1.) return u;

    float t=u*float(256);
    int i=min(int(t),256-1);
    float f=t-float(i);

    float hi=texelFetch(tex,ivec2(i,0),0).r;
    if(hi<=0.) return u;

    float lo=(i==0)?0.:texelFetch(tex,ivec2(i-1,0),0).r;

    slope=max((hi-lo)*float(256),1e-3);
    return mix(lo,hi,f);
}

vec2 rtwsmWarp(vec2 clipXY, out vec2 slope){
    vec2 uv=clipXY*.5+.5;
    vec2 w;
    w.x=rtwsmWarp1D(samplerWarpX,uv.x,slope.x);
    w.y=rtwsmWarp1D(samplerWarpY,uv.y,slope.y);
    return w*2.-1.;
}

vec3 worldSpacePosition(vec2 uv, float depth) {
    vec4 clip=vec4(uv*2.-1.,depth*2.-1.,1.);
    vec4 viewSpace=gbufferProjectionInverse*clip;
    viewSpace/=viewSpace.w;
    vec4 worldSpace=gbufferModelViewInverse*viewSpace;
    return worldSpace.xyz;
}

vec4 toShadowClip(vec3 worldPos){
    vec4 c=shadowProjection*(shadowModelView*vec4(worldPos,1.));
    return vec4(c.xyz/c.w,1.);
}

vec2 bluenoise(vec2 fragCoord){
    return texelFetch(noisetex,ivec2(fragCoord)&127,0).rg;
}

float sampleShadow(vec3 worldPos, vec3 n, float NdotL){
    vec4 clip = toShadowClip(worldPos);

    vec2 slope;
    rtwsmWarp(clip.xy,slope);
    vec2 texelWorld=vec2(abs(2./shadowProjection[0][0]),abs(2./shadowProjection[1][1]))/(float(shadowMapResolution)*slope);
    float texel=max(texelWorld.x, texelWorld.y);

    float sinT=sqrt(max(1.-NdotL*NdotL,0.));
    float tanT=min(sinT/max(NdotL,.05),4.);

    vec3 offsetPos=worldPos+n*texel*1.*(.5+sinT);

    vec4 c=toShadowClip(offsetPos);
    vec2 sampleSlope;
    vec2 warpedXY=rtwsmWarp(c.xy,sampleSlope);
    vec3 sp=vec3(warpedXY,c.z)*.5+.5;

    if(sp.x<0.||sp.x>1.||sp.y<0.||sp.y>1.||sp.z<0.||sp.z>1.){
        return 1.;
    }

    vec2 ortho=vec2(abs(2./shadowProjection[0][0]),abs(2./shadowProjection[1][1]));
    float depthRange=2./abs(shadowProjection[2][2]);

    vec2 sampleTexelWorld=ortho/(float(shadowMapResolution)*sampleSlope);
    float sampleTexel=max(sampleTexelWorld.x,sampleTexelWorld.y);

    float zBias=sampleTexel*(.25+1.*tanT)*abs(shadowProjection[2][2])*.5;
    float z=sp.z-zBias;

    float texelUV=1./float(shadowMapResolution);
    vec2 bn=bluenoise(gl_FragCoord.xy)*6.2831853;

    //blocker
    vec2 searchUV=min(depthRange*.0047*sampleSlope/ortho,vec2(64.*texelUV));
    float searchBias=.0025*min(tanT,1.5);
    float blockerSum=0.;
    float blockers=0.;
    for(int i=0;i<12;i++){
        float a=float(i)*2.3999632+bn.x;
        vec2 p=sqrt((float(i)+.5)/12.)*vec2(cos(a),sin(a));
        float d=texture(shadowtex1,sp.xy+p*searchUV).r;
        if(d<z-length(p)*searchBias){
            blockerSum+=d;
            blockers+=1.;
        }
    }

    //penumbra
    float avgBlocker=(blockers>.5)?blockerSum/blockers:z;
    float penumbraWorld=(z-avgBlocker)*depthRange*.0047;
    vec2 filterUV=max(penumbraWorld*sampleSlope/ortho,vec2(1.5*texelUV));

    // filter
    float radiusBias=penumbraWorld*tanT*abs(shadowProjection[2][2])*.25;
    float occ=0.;
    for(int i=0;i<12;i++){
        float a=float(i)*2.3999632+bn.y;
        vec2 p=sqrt((float(i)+.5)/12.)*vec2(cos(a),sin(a));
        float d=texture(shadowtex1,sp.xy+p*filterUV).r;
        occ+=(z-length(p)*radiusBias>d)?1.:0.;
    }
    occ/=12.;

    float edge=max(abs(clip.x),abs(clip.y));
    float fade=1.-smoothstep(.85,1.,edge);

    return 1.-occ*(1.-.35)*fade;
}

void main(){
    vec4 albedo=texture(colortex0,texcoord);
    float depth=texture(depthtex0,texcoord).r;

    vec3 worldPos=worldSpacePosition(texcoord,depth);

    vec3 c=cross(dFdx(worldPos),dFdy(worldPos));
    vec3 n=c/max(length(c),1e-8);
    if(dot(n,worldPos)>0.) n=-n;

    vec3 L=normalize(mat3(gbufferModelViewInverse)*shadowLightPosition);
    float NdotL=clamp(dot(n,L),0.,1.);

    float shadow=1.;

    if(depth<1.){
        vec4 shadowClip=toShadowClip(worldPos);

        vec2 uv=shadowClip.xy*.5+.5;
        if(uv.x>=0.&&uv.x<=1.&&uv.y>=0.&&uv.y<=1.){
            int binX=clamp(int(uv.x*float(256)),0,256-1);
            int binY=clamp(int(uv.y*float(256)),0,256-1);
            imageAtomicAdd(histX,ivec2(binX,0),1u);
            imageAtomicAdd(histY,ivec2(binY,0),1u);
        }

        shadow=sampleShadow(worldPos,n,NdotL);
    }

    color=vec4(albedo.rgb*shadow,albedo.a);
}