

#include "/settings.glsl"
#include "/lib/utility/uniforms.glsl"

#ifdef vsh

    out vec4 glcolor;
    out vec2 texcoord;
    out vec2 vlightmap;
    out vec3 vNormal;
    out vec3 vWorldPos;

    void main(){
        glcolor=gl_Color;
        texcoord=(gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;
        vlightmap=(gl_TextureMatrix[1]*gl_MultiTexCoord1).xy;
        vNormal=normalize(mat3(gbufferModelViewInverse)*(gl_NormalMatrix*gl_Normal));
        vWorldPos=(gbufferModelViewInverse*(gl_ModelViewMatrix*gl_Vertex)).xyz;

        gl_Position=taaClip(gl_ProjectionMatrix*gl_ModelViewMatrix*gl_Vertex);
    }

#endif

#ifdef fsh

    #include "/lib/surface/labpbr.glsl"

    uniform vec4 entityColor;

    in vec4 glcolor;
    in vec2 texcoord;
    in vec2 vlightmap;
    in vec3 vNormal;
    in vec3 vWorldPos;

    uniform int entityId;

    /* RENDERTARGETS: 0,3,13,14 */
    layout(location=0) out vec4 color;
    layout(location=1) out uvec4 color1;
    layout(location=2) out vec4 color2;
    layout(location=3) out vec4 color3;

    void main(){
        vec4 albedo=texture(tex,texcoord,log2(RS))*glcolor;
        vec2 lm=clamp((vlightmap-.03125)/.9375,0.,1.);

        if(entityId==1){
            if(albedo.a<.1) discard;

            Material m=materialDefault(toLinear(albedo.rgb));
            vec4 spec=texture(specular,texcoord,log2(RS));
            spec.g=textureLod(specular,texcoord,0.).g;
            m=decodeLabPBR(spec,toLinear(albedo.rgb));
            m.id=MAT_ENTITY;

            albedo.rgb=mix(albedo.rgb,entityColor.rgb,entityColor.a);

            color=vec4(albedo.rgb,1.);
            color1=gbPack(m,normalize(vNormal),lm,1.);
            color2=vec4(0.);
            color3=vec4(0.);
        }else{
            if(albedo.a<.05) discard;

            albedo.rgb=mix(albedo.rgb,entityColor.rgb,entityColor.a);

            vec3 N=normalize(vNormal);
            if(dot(N,-vWorldPos)<0.) N=-N;
            color2=vec4(N,-(4.+lm.y*.99));
            color3=albedo;

            ivec2 px=ivec2(gl_FragCoord.xy);
            color=texelFetch(colortex0,px,0);
            color1=texelFetch(colortex3,px,0);
        }
    }

#endif
