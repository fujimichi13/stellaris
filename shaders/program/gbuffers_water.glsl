

#include "/settings.glsl"
#include "/lib/utility/uniforms.glsl"

#ifdef vsh

    in vec4 mc_Entity;

    out vec4 glcolor;
    out vec2 texcoord;
    out vec2 vlightmap;
    out vec3 vNormal;
    out vec3 vWorldPos;
    out float iswater;

    void main(){
        glcolor=gl_Color;
        texcoord=(gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;
        vlightmap=(gl_TextureMatrix[1]*gl_MultiTexCoord1).xy;

        iswater=(abs(mc_Entity.x-1.)<.5)?1.:0.;

        vNormal=normalize(mat3(gbufferModelViewInverse)*(gl_NormalMatrix*gl_Normal));

        vec4 viewPos=gl_ModelViewMatrix*gl_Vertex;
        vWorldPos=(gbufferModelViewInverse*viewPos).xyz;
        gl_Position=gl_ProjectionMatrix*viewPos;
        #ifdef TAA_ENABLED
            gl_Position.xy+=taaJitter*gl_Position.w;
        #endif
    }

#endif

#ifdef fsh

    #include "/lib/atmosphere/scattering.glsl"
    #include "/lib/surface/brdf.glsl"
    #include "/lib/water/water.glsl"

    /*
    const int colortex13Format = RGBA16F;
    const int colortex15Format = RGBA16F;
    */

    in vec4 glcolor;
    in vec2 texcoord;
    in vec2 vlightmap;
    in vec3 vNormal;
    in vec3 vWorldPos;
    in float iswater;

    /* RENDERTARGETS: 13,14 */
    layout(location = 0) out vec4 color;
    layout(location = 1) out vec4 color1;

    void main(){
        vec4 albedo=texture(tex,texcoord)*glcolor;
        vec2 lm=saturate((vlightmap-.03125)/.9375);

        if(iswater<.5){
            if(albedo.a<.05) discard;
            color=vec4(0.);
            color1=albedo;
            return;
        }

        float dist=length(vWorldPos);
        vec3 V=-vWorldPos/dist;

        vec3 Ng=normalize(vNormal);
        if(dot(Ng,V)<0.) Ng=-Ng;

        float fade=smoothstep(.5,.9,abs(Ng.y))*(1.-smoothstep(64.,200.,dist));

        vec3 Nw=wNP((vWorldPos+cameraPosition).xz,V);
        Nw.y*=sign(Ng.y);

        color=vec4(normalize(mix(Ng,Nw,fade)),1.);
        color1=vec4(glcolor.rgb,lm.y);
    }

#endif