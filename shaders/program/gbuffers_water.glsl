

#include "/settings.glsl"
#include "/lib/utility/uniforms.glsl"

#ifdef vsh

    in vec4 mc_Entity;
    in vec4 at_tangent;

    out vec4 glcolor;
    out vec2 texcoord;
    out vec2 vlightmap;
    out vec3 vNormal;
    out vec3 vTangent;
    out vec3 vBitangent;
    out vec3 vWorldPos;
    out float iswater;
    out float isglass;
    flat out float vGlass;

    void main(){
        glcolor=gl_Color;
        texcoord=(gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;
        vlightmap=(gl_TextureMatrix[1]*gl_MultiTexCoord1).xy;

        iswater=(abs(mc_Entity.x-1.)<.5)?1.:0.;

        int gi=int(mc_Entity.x+.5);
        float gk=0.;
        if(gi>=200&&gi<218) gk=1.;
        else if(gi>=100&&gi<118) gk=2.;
        int gn=(gk>0.)?(gi%100):-1;
        vGlass=(abs(mc_Entity.x-3.)<.5)?1.:-1.;
        isglass=(vGlass>0.)?3.:((abs(mc_Entity.x-2.)<.5)?2.:3.);

        vNormal=normalize(mat3(gbufferModelViewInverse)*(gl_NormalMatrix*gl_Normal));
        vec3 T=normalize(mat3(gbufferModelViewInverse)*(gl_NormalMatrix*at_tangent.xyz));
        vTangent=T;
        vBitangent=normalize(cross(T,vNormal)*at_tangent.w);

        vec4 viewPos=gl_ModelViewMatrix*gl_Vertex;
        vWorldPos=(gbufferModelViewInverse*viewPos).xyz;
        gl_Position=taaClip(gl_ProjectionMatrix*viewPos);
    }

#endif

#ifdef fsh

    #include "/lib/atmosphere/scattering.glsl"
    #include "/lib/surface/brdf.glsl"
    #include "/lib/surface/labpbr.glsl"
    #include "/lib/water/water.glsl"

    in vec4 glcolor;
    in vec2 texcoord;
    in vec2 vlightmap;
    in vec3 vNormal;
    in vec3 vTangent;
    in vec3 vBitangent;
    in vec3 vWorldPos;
    in float iswater;
    in float isglass;
    flat in float vGlass;

    /* RENDERTARGETS: 13,14,12 */
    layout(location=0) out vec4 color;
    layout(location=1) out vec4 color1;
    layout(location=2) out vec4 color2;
    
    void main(){
        vec4 albedo=texture(tex,texcoord)*glcolor;
        vec2 lm=saturate((vlightmap-.03125)/.9375);

        bool glass=vGlass>-.5;
        if(glass){
            vec4 bl=textureLod(tex,texcoord,2.5);
            vec3 gc=mix(vec3(1.),bl.rgb,smoothstep(0.,.5,bl.a));
            albedo=vec4(gc,clamp(bl.a,.08,.9));
        }

        if(iswater<.5){
            if(!glass&&albedo.a<.05) discard;

            float nao;
            vec3 Ng0=decodeLabPBRNormal(texture(normals,texcoord,log2(RS)),mat3(normalize(vTangent),normalize(vBitangent),normalize(vNormal)),nao);
            if(dot(Ng0,-vWorldPos)<0.) Ng0=-Ng0;

            color=vec4(Ng0,-(floor(isglass+.5)+lm.y*.99));
            color1=albedo;

            float gcode=floor(isglass+.5);
            float gthick=(gcode<1.5)?.125:((gcode<2.5)?1.:((gcode<3.5)?.5:.3));
            color2=vec4(-log(clamp(pow(albedo.rgb,vec3(2.2)),.02,1.))*gthick*.6,0.);
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
        color2=vec4(0.);
    }

#endif